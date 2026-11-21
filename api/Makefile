SHELL := /bin/bash
.DEFAULT_GOAL := ci
OUT := .out
ACTIONLINT := github.com/rhysd/actionlint/cmd/actionlint@v1.7.7

# Local settings: copy .env.example to .env (gitignored). Variables are exported to every recipe.
-include .env
DATABASE_URL ?= postgres://wuppa:wuppa@localhost:5432/wuppa?sslmode=disable
export

.PHONY: db-up db-down migrate migrate-down seed sqlc openapi-lint run \
	test-unit test-integration test check lint lint-workflows lint-selftest test-selftest ci

db-up:
	@bash scripts/db.sh up

db-down:
	@bash scripts/db.sh down

migrate:
	@bash scripts/migrate.sh up

migrate-down:
	@bash scripts/migrate.sh down

seed:
	@bash scripts/unavailable.sh seed SEED-01 cmd/seed/main.go

sqlc:
	@bash scripts/unavailable.sh sqlc BE-02 sqlc.yaml

openapi-lint:
	@bash scripts/unavailable.sh openapi-lint BE-01 openapi.yaml

run:
	@go run ./cmd/api

test-unit:
	@bash scripts/test.sh unit

test-integration:
	@bash scripts/test.sh integration

test: test-unit test-integration

check: lint test

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

test-selftest:
	@bash scripts/test-selftest.sh

ci: lint lint-workflows lint-selftest test-selftest test
