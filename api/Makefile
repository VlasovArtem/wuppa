SHELL := /bin/bash
.DEFAULT_GOAL := ci
OUT := .out
ACTIONLINT := github.com/rhysd/actionlint/cmd/actionlint@v1.7.7

.PHONY: lint lint-workflows lint-selftest ci

lint:
	@bash scripts/lint.sh

lint-workflows:
	@mkdir -p $(OUT)
	@files=$$(ls ../.github/workflows/*.yml ../.github/workflows/*.yaml 2>/dev/null); \
	if [ -z "$$files" ]; then \
		echo "RESULT: ERROR lint-workflows no workflow files found in .github/workflows"; exit 2; \
	fi; \
	NO_COLOR=1 go run $(ACTIONLINT) -no-color $$files >$(OUT)/lint-workflows.log 2>&1; code=$$?; \
	if [ $$code -eq 0 ]; then \
		echo "RESULT: PASS lint-workflows issues=0"; exit 0; \
	fi; \
	issues=$$(grep -Ec '^[^ :]+:[0-9]+:[0-9]+: ' $(OUT)/lint-workflows.log); \
	if [ $$code -eq 1 ] && [ $$issues -gt 0 ]; then \
		grep -E '^[^ :]+:[0-9]+:[0-9]+: ' $(OUT)/lint-workflows.log | head -n 60; \
		echo "RESULT: FAIL lint-workflows issues=$$issues log=$(OUT)/lint-workflows.log"; exit 1; \
	fi; \
	head -n 20 $(OUT)/lint-workflows.log; \
	echo "RESULT: ERROR lint-workflows actionlint exited $$code (see $(OUT)/lint-workflows.log)"; exit 2

lint-selftest:
	@bash scripts/lint-selftest.sh

ci: lint lint-workflows lint-selftest
