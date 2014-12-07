PLT_APPS?=erts kernel stdlib
DIALYZER_OPTS?=-Werror_handling -Wrace_conditions -Wunmatched_returns -Wunderspecs

REBAR?=$(CURDIR)/rebar
REBAR_URL?=https://github.com/rebar/rebar/releases/download/2.5.1/rebar

RELX?=$(CURDIR)/relx
RELX_URL?=https://github.com/erlware/relx/releases/download/v1.0.4/relx

RELX_OPTS?=

PROJECT_PLT=$(CURDIR)/.project_plt

ERL=$(shell which erl)
ifeq ($(ERL),)
$(error "Erlang not available on this system")
endif

export REBAR
export RELX

.PHONY: rebar-all rebar-compile rebar-clean rebar-test \
        rebar-get-deps rebar-release dialyzer

DEFAULT+=rebar-compile
CLEAN+=rebar-clean
TEST+=rebar-test
GET_DEPS+=rebar-get-deps
RELEASE+=rebar-release
TEST+=rebar-test

rebar-get-deps: $(REBAR) .build/erlang_deps

.build/erlang_deps: rebar.config
	$(REBAR) get-deps
	@mkdir -p .build
	@touch .build/erlang_deps

rebar-compile: rebar-get-deps $(REBAR)
	$(REBAR) compile

rebar-release: rebar-compile $(RELX)
	$(RELX) $(RELX_OPTS)

eunit: rebar-compile clean-common-test-data
	$(REBAR) skip_deps=true eunit

ct: rebar-compile clean-common-test-data
	$(REBAR) skip_deps=true ct

rebar-test: rebar-compile eunit ct

define download
	wget -O $(1) $(2) || rm $(1)
	chmod +x $(1)
endef

$(REBAR):
	@$(call download,$(REBAR),$(REBAR_URL))

$(RELX):
	@$(call download,$(RELX),$(RELX_URL))

$(PROJECT_PLT):
	@echo Building local plt at $(PROJECT_PLT)
	@echo
	dialyzer --output_plt $(PROJECT_PLT) --build_plt \
	         --apps $(PLT_APPS) -r deps

dialyzer: rebar-compile $(PROJECT_PLT)
	dialyzer --plt $(PROJECT_PLT) \
	         --fullpath \
	         $(DIALYZER_OPTS) \
	         --src -r src

rebar-clean:
	$(REBAR) clean
