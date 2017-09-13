# include root makefile
ifndef ROOT_MAKEFILE_MK
include ../../../../Makefile
endif

# prevent rules from being evaluated/included multiple times
ifndef $(abspath $(lastword $(MAKEFILE_LIST)))_MK
$(abspath $(lastword $(MAKEFILE_LIST)))_MK := 1

# uncomment to disable generate test related targets in this directory
#TEST_TARGET := false

# uncomment to disable generate pony related targets (build/test/clean) for pony sources in this directory
PONY_TARGET := false

# uncomment to disable generate exs related targets (build/test/clean) for elixir sources in this directory
EXS_TARGET := false

# uncomment to disable generate docker related targets (build/push) for Dockerfile in this directory
DOCKER_TARGET := false

# uncomment to disable generate recursing into Makefiles of subdirectories
RECURSE_SUBMAKEFILES := false

SEQUENCE_WINDOW_PYTHON_PATH := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))


# standard rules generation makefile
include $(rules_mk_path)


build-testing-correctness-apps-sequence_window_python: build-machida
build-testing-correctness-apps-sequence_window_python: build-testing-correctness-apps-sequence_window-validator
test-testing-correctness-apps-sequence_window_python: build-testing-correctness-apps-sequence_window_python
test-testing-correctness-apps-sequence_window_python: sequence_window_python_test

sequence_window_python_test:
	cd $(SEQUENCE_WINDOW_PYTHON_PATH) && \
	integration_test --sequence-sender '(0,1000]' \
	  --log-level error \
		--command 'machida --application-module sequence_window' \
		--validation-cmd 'validator -e 1000 -a -i' \
		--output 'received.txt' \
		--workers 2 \
		--giles-mode \
		--sink-expect 1000


# args to RUN_DAGON and RUN_DAGON_SPIKE: $1 = test name; $2 = ini file; $3 = timeout; $4 = wesley test command, $5 = include in CI
# NOTE: all paths must be relative to buffy directory (use buffy_path variable)

##<NAME OF TARGET>: #used as part of `make help` command ## <DESCRIPTION OF TARGET>
#$(eval $(call RUN_DAGON\
#,<NAME OF TARGET> \
#,$(buffy_path)/<PATH TO INI FILE> \
#,<TIMEOUT VALUE> \
#,<WESLEY TEST COMMAND> \
#,<INCLUDE IN CI>))

# end of prevent rules from being evaluated/included multiple times
endif