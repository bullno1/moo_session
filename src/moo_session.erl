-module(moo_session).
-behaviour(cowboy_middleware).
-export([execute/2]).
-export([get/1, set/2, delete/1]).

execute(Req, Env) ->
	SessionOpts = proplists:get_value(moo, Env, application:get_all_env(moo_session)),
	Req2 = cowboy_req:set_meta(moo_opts, SessionOpts, Req),
	{ok, Req2, Env}.

-spec get(cowboy_req:req()) -> {jwt:claim_set() | undefined, cowboy_req:req()}.
get(Req) ->
	{SessionOpts, Req2} = cowboy_req:meta(moo_opts, Req, []),
	case cowboy_req:cookie(<<"sid">>, Req2) of
		{undefined, Req3} -> {undefined, Req3};
		{Cookie, Req3} ->
			case jwt:parse_token(Cookie, proplists:get_value(supported_algorithms, SessionOpts, [])) of
				{ok, #{<<"exp">> := Exp} = ClaimSet} ->
					% Validate exp and refresh
					{MegaSecs, Secs, _} = os:timestamp(),
					Now = MegaSecs * 1000000 + Secs,
					RefreshThreshold = proplists:get_value(refresh_threshold, SessionOpts, 0),
					if
						Exp =< Now -> {undefined, Req3}; %expired
						Exp =< (Now + RefreshThreshold) -> %need refreshing
							SessionLength = proplists:get_value(session_length, SessionOpts, 0),
							SigningAlgorithm = proplists:get_value(signing_algorithm, SessionOpts, none),
							NewExp = Now + SessionLength,
							NewToken = jwt:issue_token(replace_exp(ClaimSet, NewExp), SigningAlgorithm),
							CookieOpts = proplists:get_value(cookie_opts, SessionOpts, []),
							Req4 = cowboy_req:set_resp_cookie(<<"sid">>, NewToken, [{max_age, SessionLength} | CookieOpts], Req3),
							{ClaimSet, Req4};
						true ->
							{ClaimSet, Req3}
					end;
				_ ->
					{ok, Req3}
			end
	end.

-spec set(jwt:claim_set(), cowboy_req:req()) -> cowboy_req:req().
set(ClaimSet, Req) ->
	{SessionOpts, Req2} = cowboy_req:meta(moo_opts, Req, []),
	SessionLength = proplists:get_value(session_length, SessionOpts, 0),
	SigningAlgorithm = proplists:get_value(signing_algorithm, SessionOpts, none),
	{MegaSecs, Secs, _} = os:timestamp(),
	Now = MegaSecs * 1000000 + Secs,
	Exp = Now + SessionLength,
	NewToken = jwt:issue_token(replace_exp(ClaimSet, Exp), SigningAlgorithm),
	CookieOpts = proplists:get_value(cookie_opts, SessionOpts, []),
	cowboy_req:set_resp_cookie(<<"sid">>, NewToken, [{max_age, SessionLength} | CookieOpts], Req2).

-spec delete(cowboy_req:req()) -> cowboy_req:req().
delete(Req) -> cowboy_req:set_resp_cookie(<<"sid">>, <<"">>, [{max_age, 0}], Req).

replace_exp(ClaimSet, Exp) when is_map(ClaimSet) -> ClaimSet#{<<"exp">> => Exp};
replace_exp(ClaimSet, Exp) when is_list(ClaimSet) -> lists:keystore(<<"exp">>, 1, ClaimSet, {<<"exp">>, Exp}).
