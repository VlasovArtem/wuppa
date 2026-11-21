# Wuppa — project guide for Claude Code

Wuppa is a family app that turns household jobs into achievements. Guardians (parents) create tasks, kids mark them done, guardians approve, kids earn points and spend them on rewards the guardians define. This repository holds the **proof of concept (POC)**: a Go API and one Flutter app for iOS and Android.

The full specification and the ordered task list are in `docs/poc-plan.md`. Read it before starting any task.

## How to work in this repo

- Work through `docs/poc-plan.md` **one task at a time, in order**. Do not start the next task until the current one meets every "Done when" check.
- Before coding a task, restate its goal and list the files you will touch. Ask if something in the spec is unclear or contradicts the code.
- After finishing a task: run the verification commands listed in the task, tick its checkbox in `docs/poc-plan.md`, and commit with the message `<TASK-ID>: <short summary>` plus a body line `Closes #<issue>` (e.g. `BE-03: guardian sign-up, login, tokens` / `Closes #8`). Every task heading in `docs/poc-plan.md` links its GitHub issue; manual steps are collected in issue #1.
- Do not add features, endpoints, tables or dependencies that the plan does not ask for. If one seems necessary, propose it first.
- Business rules (limits, points, permissions) live in the API. The app never decides them on its own.
- Never log personal data (emails, nicknames, tokens, passwords).

## Repository layout

```
api/                    Go API (module: github.com/VlasovArtem/wuppa/api)
  cmd/api/main.go
  internal/http/        handlers, middleware, routing
  internal/auth/        tokens, password hashing
  internal/domain/      business rules: periods, limits, ledger, streaks, badges
  internal/db/          sqlc queries (queries/*.sql) and generated code
  internal/push/        FCM client
  internal/mail/        SMTP mailer, EN/RU email templates
  migrations/           goose SQL migrations
  openapi.yaml          API contract
  docker-compose.yml    local PostgreSQL
  Makefile
app/                    Flutter app
  lib/core/             theme, routing, storage, api client setup
  lib/api/              generated OpenAPI client
  lib/l10n/             app_en.arb, app_ru.arb
  lib/features/<name>/  one folder per feature
docs/
  poc-plan.md           specification + task list (source of truth)
```

## Stack

| Part | Choice |
| --- | --- |
| API language | Go 1.23+ |
| Router | `github.com/go-chi/chi/v5` |
| Database | PostgreSQL 16 |
| DB access | `github.com/jackc/pgx/v5` + `sqlc` |
| Migrations | `github.com/pressly/goose/v3` (SQL files) |
| Logging | `log/slog`, JSON handler |
| Password hashing | `golang.org/x/crypto/argon2` (argon2id) |
| JWT | `github.com/golang-jwt/jwt/v5` |
| UUIDs | `github.com/google/uuid` (v7) |
| Push | Firebase Cloud Messaging HTTP v1 |
| Email | `net/smtp` (standard library); Mailpit locally |
| Tests | standard `testing`, `testify/require`, real PostgreSQL via docker compose |
| Mobile | Flutter (stable), Riverpod, dio, go_router, flutter_secure_storage, firebase_messaging, flutter_timezone, share_plus, gen-l10n (EN + RU) |

## Commands

API (run from `api/`):

```
make db-up              # start PostgreSQL in docker
make migrate            # apply migrations
make seed               # load demo data
make run                # start the API on :8080
make test-unit          # unit tests          [PKG=./internal/domain/...] [RUN=TestPeriodStart]
make test-integration   # integration tests (starts the DB itself)  [PKG=] [RUN=]
make test               # both
make lint               # go vet + golangci-lint
make check              # lint + test
make sqlc               # regenerate sqlc code
make openapi-lint       # validate openapi.yaml
```

App (run from `app/`):

```
make test-unit          # flutter test, summarised   [NAME=<file or test name>]
make lint               # dart format check + flutter analyze
make check              # lint + tests
flutter pub get
flutter run --flavor local -t lib/main_local.dart
dart run build_runner build --delete-conflicting-outputs
```

## Conventions

- API: REST + JSON under `/v1`; timestamps RFC 3339 UTC; IDs are UUID v7.
- Errors: HTTP status + `{"error": {"code": "<stable_code>", "message": "<human text>"}}`. Codes are listed in `docs/poc-plan.md`.
- Every handler checks that the resource belongs to the caller's family. Return **404** (not 403) for another family's resources.
- Kid device tokens get **403** on guardian-only endpoints.
- Everything that changes points runs in one database transaction.
- Go: small packages, no global state except config; pass `context.Context`; table-driven tests.
- Every user-facing text exists in English and Russian (ARB files in the app, templates / push texts in the API).
- Flutter: one folder per feature with `data/`, `providers/`, `ui/`; no business logic in widgets.
- Keep `openapi.yaml` in sync with handlers in the same commit.

## Step workflow

Used by the global `tdd-step` skill (`~/.claude/skills/tdd-step`). Each task is one step: one branch, one PR.

- Plan document: `docs/poc-plan.md`. Task headings: `#### [ ] <ID> · <title> · [#<n>](<issue>) · plan: opus|direct · review: fast|standard|heavy`.
- Task folders: `docs/tasks/<ID>-<slug>/` with `plan.md`, `notes.md`, `log.md`, `review.md`, `result.md`, `handoff.md`. Lasting decisions: `docs/decisions.md`.
- Scratch: `.steps/<ID>/` (gitignored): briefs and reviewer files.
- Branch: `step/<ID>-<slug>` from `origin/master`; PR to `master` with `Closes #<n>`; the user merges (squash).
- GitHub: repository `VlasovArtem/wuppa`. Run every gh command as `GH_TOKEN=$(gh auth token -u VlasovArtem) gh ...` (another gh account may be active).
- Tests are written first (RED), then the code (GREEN). Before SET-02 / SET-03 exist, use `go test` / `flutter test` directly and note it in `log.md`.

### Agent-friendly command contract

`make -C api test-unit|test-integration|lint` and `make -C app test-unit|test-integration|lint` behave the same way:

- Non-interactive, no colours or progress bars (`NO_COLOR=1`), deterministic (`-count=1`), bounded (`-timeout 5m`).
- Narrowing: `PKG=` and `RUN=` for Go, `NAME=` for Flutter.
- The full output goes to `<api|app>/.out/<target>.log` (gitignored); stdout stays short.
- On failure, stdout lists only the failing parts, at most 60 lines: per failing test `FAIL <package>.<Test>/<sub> (<file>:<line>)` and its message lines; per lint finding `<file>:<line>:<col>: <message> (<linter>)`.
- The last line is always exactly one of:
  - `RESULT: PASS <target> tests=<n> skipped=<n> duration=<s>s` (lint: `issues=0`)
  - `RESULT: FAIL <target> failed=<n> log=<path>` (lint: `issues=<n>`)
  - `RESULT: ERROR <target> <reason>` (environment problem, e.g. Docker not running, unknown `PKG`)
- Exit codes: 0 pass, 1 test or lint failure, 2 environment or usage error.
