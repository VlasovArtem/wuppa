---
task: SET-02
title: Local environment
issue: https://github.com/VlasovArtem/wuppa/issues/3
branch: step/SET-02-local-environment
plan_model: opus
review: standard
status: approved
approved_at: 2026-11-21 (in chat, after the dialog answer Stop)
---

# SET-02 · Local environment

## Goal

`make -C api <target>` gives a working local stack (PostgreSQL 16 + Mailpit in Docker, goose migrations) and
agent-friendly test targets: `test-unit`, `test-integration`, `test`, `check`, each ending with one `RESULT:` line.
CI runs the same targets through `make -C api ci`.

## Context

- Spec: `docs/poc-plan.md` SET-02 (around line 445), configuration table in section 2, contract in `CLAUDE.md` ("Agent-friendly command contract").
- Depends on SET-01: scripts own the exit codes, make only wraps them (`docs/decisions.md`); `ci` is what CI runs.
- Later steps fill targets that have no input yet: `sqlc` (BE-02), `openapi-lint` (BE-01), `seed` (SEED-01).

## Decisions for this step

1. **Every target ends with a `RESULT:` line**, not only tests and lint (db-up, migrate, ...). Scripts in `api/scripts/` own it.
2. **Targets without input yet** exit 2 with `RESULT: ERROR <target> not available until <task> (<missing file>)`:
   `sqlc` (no `sqlc.yaml`), `openapi-lint` (no `openapi.yaml`), `seed`. No fake passes.
3. **Tools run with `go run <module>@<pinned version>`**, never added to `go.mod`: goose v3 (pin the latest v3 release; check
   with `go list -m -versions github.com/pressly/goose/v3`). `api/go.mod` stays dependency-free in this step.
4. **Integration tests** = files with `//go:build integration`. `test-integration` runs only packages that contain such files,
   with `-tags integration -p 1` (their unit tests run too; accepted). No such package → `RESULT: PASS test-integration tests=0`.
5. **`test-integration` prepares the database itself**: Docker missing or not running → ERROR exit 2; otherwise
   `docker compose up -d --wait db`, create `wuppa_test` if absent, run goose `up` on it, export
   `DATABASE_URL=postgres://wuppa:wuppa@localhost:5432/wuppa_test?sslmode=disable` for the tests.
6. **CI uses Docker Compose, not a service container.** Remove the `postgres` service from `api.yml` (it would take port
   5432); CI then exercises the same `db-up` path as a developer. Port 5432 busy → ERROR naming the port.
7. **Makefile env:** `-include .env` and `export`; defaults for `DATABASE_URL` match `.env.example`. `.env` stays gitignored.
8. **Logs:** `api/.out/<target>.log` holds the readable test output; `api/.out/<target>.json` the raw `go test -json` stream.
9. **testsummary** computes the duration from the first and last event `Time` (deterministic for fixtures), counts a failed
   build as a failure (`failed=` includes it) and prints `BUILD FAIL <pkg>: <file>:<line>:<col>: <message>` for it.

## Files to touch

| File | New / changed | Purpose |
| --- | --- | --- |
| `api/docker-compose.yml` | new | `db`: `postgres:16`, wuppa/wuppa/wuppa, 5432, named volume, `pg_isready` health check; `mailpit`: `axllent/mailpit` pinned tag, 1025 + 8025 |
| `api/.env.example` | new | every variable from section 2 with local defaults (`SMTP_URL=smtp://localhost:1025`) |
| `api/Makefile` | changed | targets from the spec + `ci`; each wraps a script |
| `api/scripts/db.sh` | new | `up` / `down` / `ensure-test-db`; Docker checks |
| `api/scripts/migrate.sh` | new | goose `up` / `down` on `DATABASE_URL`; zero migrations is a PASS (`migrations=0`) |
| `api/scripts/test.sh` | new | `unit` / `integration`: PKG, RUN, `-count=1 -timeout 5m`, NO_COLOR, pipes JSON to testsummary, unknown PKG → exit 2 |
| `api/scripts/unavailable.sh` | new | the ERROR line for targets of decision 2 |
| `api/tools/testsummary/main.go` (+ `summary.go`) | new | reads `go test -json` on stdin; flags `-target`, `-log` |
| `api/tools/testsummary/summary_test.go` + `testdata/*.jsonl` | new | unit tests, fixtures captured from real `go test -json` runs |
| `api/internal/testenv/testenv.go` | new | `DatabaseURL(t testing.TB) string`: fails the test with a clear message if `DATABASE_URL` is empty (BE-02 builds on it) |
| `api/internal/testenv/testenv_integration_test.go` | new | `//go:build integration`: the database from `DATABASE_URL` accepts a TCP connection |
| `api/scripts/test-selftest.sh` | new | end-to-end checks of the targets (RED list 11-15) |
| `api/migrations/.gitkeep` | new | goose directory |
| `.github/workflows/api.yml` | changed | drop the postgres service; `make -C api ci` |
| `.gitignore` | changed | `api/internal/zztestselftest/` |
| `CLAUDE.md` | changed | command list: note `RESULT` on every target and the ERROR-until targets |

## Tests first (RED list)

testsummary (unit, `api/tools/testsummary`), fixtures in `testdata/`:

| # | Test | Kind | Scenario | Expected |
| --- | --- | --- | --- | --- |
| 1 | `TestSummary/all_pass` | unit | 3 pass, 1 skip | only `RESULT: PASS test-unit tests=3 skipped=1 duration=<s>s`; exit 0 |
| 2 | `TestSummary/one_failure` | unit | `t.Errorf` at `foo_test.go:12` | `FAIL <pkg>.TestX (foo_test.go:12)` + its message line, then `RESULT: FAIL test-unit failed=1 log=<path>`; passing tests not listed; exit 1 |
| 3 | `TestSummary/subtest_failure` | unit | `TestX/case_b` fails | listed as `TestX/case_b` once; parent `TestX` not listed again |
| 4 | `TestSummary/panic` | unit | test panics | listed as failed with the `panic:` line and the first stack frame inside the module |
| 5 | `TestSummary/build_error` | unit | package does not compile | `BUILD FAIL <pkg>: <file>:<line>:<col>: <msg>`; `failed=1`; exit 1 |
| 6 | `TestSummary/line_cap` | unit | 100 failing tests | at most 60 summary lines incl. `... <k> more lines in <log>`, then the RESULT line |
| 7 | `TestSummary/writes_log` | unit | any input | log file contains the plain test output (Output fields, in order) |
| 8 | `TestSummary/no_events` | unit | empty stdin | `RESULT: ERROR test-unit no test events`; exit 2 |
| 9 | `TestSummary/no_test_files` | unit | only "no test files" packages | `RESULT: PASS test-unit tests=0 skipped=0 ...` |
| 10 | `TestDatabaseReachable` | integration | DB from `DATABASE_URL` | TCP connect succeeds |

Target self-test (`bash api/scripts/test-selftest.sh`, temp package `internal/zztestselftest`, removed by a trap):

| # | Check | Expected |
| --- | --- | --- |
| 11 | failing temp test, `scripts/test.sh unit` with its PKG | stdout = its `FAIL ... (zz_test.go:<n>)` lines + `RESULT: FAIL`; exit 1 |
| 12 | passing temp test | `RESULT: PASS test-unit tests=1 ...`; exit 0 |
| 13 | `PKG=./nope/...` | `RESULT: ERROR test-unit ...`; exit 2 |
| 14 | stop the `db` container, then `make test-integration` | `RESULT: PASS test-integration tests=1 ...`; `db` healthy afterwards; `wuppa_test` exists |
| 15 | `make migrate && make migrate-down && make migrate` | each ends with `RESULT: PASS`; exit 0 |

Stubs for RED: `testsummary` with a `Summarize(r io.Reader, target, logPath string) (out string, code int)` that returns
`"", 0`; `testenv.DatabaseURL` returning `""`. Scripts do not exist yet, so 11-15 fail.

## Implementation steps

1. testsummary (tests 1-9 green), then `scripts/test.sh` and the `test-unit` target.
2. `docker-compose.yml`, `.env.example`, `scripts/db.sh`, `db-up` / `db-down`.
3. `scripts/migrate.sh`, `migrate` / `migrate-down`; `ensure-test-db`; `test-integration`, `test`, `check`.
4. `testenv` (+ test 10), `unavailable.sh` targets, `run` (`go run ./cmd/api`).
5. `test-selftest.sh`; `ci: lint lint-workflows lint-selftest test-selftest test`; `api.yml` without the service; `CLAUDE.md` commands.

## Verification

| Command | Expected last line |
| --- | --- |
| `make -C api test-unit` | `RESULT: PASS test-unit tests=<n> ...` |
| `make -C api test-integration` | `RESULT: PASS test-integration tests=<n> ...` |
| `bash api/scripts/test-selftest.sh` | `test-selftest: PASS` |
| `make -C api lint` | `RESULT: PASS lint issues=0` |
| `make -C api ci` | exit 0; and the PR's CI checks green |

"Done when" mapping: db-up + migrate → 15; testsummary unit tests → 1-9; failing test / DB down / unknown PKG → 11, 14, 13.

## Out of scope

- Migrations, sqlc config, OpenAPI file, seed data, server code (BE-01, BE-02, SEED-01). Any dependency in `go.mod`.
- Flutter / app targets (SET-03).

## Risks and open questions

- `go run goose@...` compiles on first use (~30 s); fine locally and in CI (Go build cache).
- goose may treat "no migration files" as an error; `migrate.sh` maps exactly that case to PASS `migrations=0`.
- A local PostgreSQL on 5432 blocks `db-up`: reported as ERROR, no automatic port change.
