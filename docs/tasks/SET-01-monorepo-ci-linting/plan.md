---
task: SET-01
title: Monorepo, CI, linting
issue: https://github.com/VlasovArtem/wuppa/issues/2
branch: step/SET-01-monorepo-ci-linting
plan_model: direct
review: fast
status: approved
approved_at: 2026-11-21
---

# SET-01 · Monorepo, CI, linting

## Goal

Repo has `api/` (Go module + placeholder main + golangci-lint v2 config + Makefile with `lint`, `lint-workflows`, `ci`) and `app/` (placeholder), cleaned root files, and two valid GitHub Actions workflows.

## Context

- Spec: docs/poc-plan.md section 9, task SET-01 (line ~434); notes.md decisions 1-9 (authoritative).
- Depends on: nothing. Decisions: docs/decisions.md (none affecting this step).

## Files to touch

| File | New / changed | Purpose |
| --- | --- | --- |
| api/go.mod | new | module github.com/VlasovArtem/wuppa/api, go 1.23 |
| api/cmd/api/main.go | new | placeholder |
| api/.golangci.yml | new | v2 format: govet, staticcheck, errcheck, gosec, revive |
| api/Makefile | new | lint, lint-workflows, ci (agent-friendly RESULT contract, log in api/.out/) |
| api/scripts/lint-selftest.sh | new | deliberate lint error must fail make lint |
| .github/workflows/api.yml | new | Go, postgres:16 service, make -C api ci |
| .github/workflows/app.yml | new | Flutter steps guarded by hashFiles('app/pubspec.yaml') |
| app/.gitkeep | new | placeholder |
| README.md | new | 2-line intro, layout, lint, link to plan |
| .gitignore | changed | add Go, Flutter, IDE, .env, api/.out/, app/.out/; keep .idea, .steps/, .out/ |
| main.go, go.mod, gitignore.gitignore (root), gitignore (untracked) | deleted | cleanup |

## Tests first (RED list)

| # | Test | Kind | Scenario | Expected |
| --- | --- | --- | --- | --- |
| 1 | `bash api/scripts/lint-selftest.sh` | script | copies bad file (unchecked error) into temp package under api/, runs `make -C api lint`, trap removes it | asserts exit 1, a `file:line:col: message (linter)` line, last line `RESULT: FAIL lint issues=<n> log=...`; also asserts clean tree `make -C api lint` exits 0 with `RESULT: PASS lint issues=0`; script exits 0 only if all hold |
| 2 | `make -C api lint-workflows` | script | actionlint via `go run github.com/rhysd/actionlint/cmd/actionlint@v1.7.7` on .github/workflows | RESULT: PASS lint-workflows issues=0 (fails while workflows missing: also errors if no workflow files found) |
| 3 | `bash api/scripts/lint-selftest.sh` extra check | script | asserts both .github/workflows/api.yml and app.yml exist, contain required paths filter and (app) hashFiles guard | exit non-zero otherwise |

RED: all fail before Makefile/config/workflows exist. Stubs: none (script-based tests).

## Implementation steps

1. Delete root main.go, go.mod, gitignore.gitignore, untracked gitignore; extend .gitignore.
2. (Orchestrator addition) `ci` = lint + lint-workflows + lint-selftest (Makefile target `lint-selftest` runs the script); CI installs golangci-lint with golangci/golangci-lint-action, `install-only: true`, version v2.15.
2b. Create api/go.mod, main.go, .golangci.yml (v2), Makefile (lint, lint-workflows, ci; RESULT contract; exit 0/1/2; ERROR if golangci-lint missing).
3. Create workflows (paths filter, setup-go go-version-file, golangci-lint-action v2.15 not required since make lint uses local binary: install it in CI via the action with install-only or go install), app.yml guard.
4. app/.gitkeep, README.md.

## Verification

| Command | Expected last line |
| --- | --- |
| `make -C api lint` | `RESULT: PASS lint issues=0` |
| `make -C api lint-workflows` | `RESULT: PASS lint-workflows issues=0` |
| `bash api/scripts/lint-selftest.sh` | exit 0, prints PASS |
| `make -C api ci` | exit 0 |

"Done when" mapping: workflows exist and valid YAML → 2, 3; deliberate lint error fails make lint → 1.

## Out of scope

- Other make targets, docker-compose, sqlc, migrations, Flutter project, any extra dependency.

## Risks and open questions

- CI needs golangci-lint binary for `make lint`: install via `golangci/golangci-lint-action` (version v2.15, install-mode binary) before `make ci`; the action's own lint run is not used.
- Compose-free: postgres service is declared but unused until SET-02.
