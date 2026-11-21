# Wuppa — project guide for Claude Code

Wuppa is a family app that turns household jobs into achievements. Guardians (parents) create tasks, kids mark them done, guardians approve, kids earn points and spend them on rewards the guardians define. This repository holds the **proof of concept (POC)**: a Go API and one Flutter app for iOS and Android.

The full specification and the ordered task list are in `docs/poc-plan.md`. Read it before starting any task.

## How to work in this repo

- Work through `docs/poc-plan.md` **one task at a time, in order**. Do not start the next task until the current one meets every "Done when" check.
- Before coding a task, restate its goal and list the files you will touch. Ask if something in the spec is unclear or contradicts the code.
- After finishing a task: run the verification commands listed in the task, tick its checkbox in `docs/poc-plan.md`, and commit with the message `<TASK-ID>: <short summary>` (e.g. `BE-03: guardian sign-up, login, tokens`).
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
make db-up        # start PostgreSQL in docker
make migrate      # apply migrations
make seed         # load demo data
make run          # start the API on :8080
make test         # go test ./... (needs db-up)
make lint         # go vet + golangci-lint
make sqlc         # regenerate sqlc code
make openapi-lint # validate openapi.yaml
```

App (run from `app/`):

```
flutter pub get
flutter analyze
flutter test
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
