# SET-02 · handoff

- Every `make -C api` target ends with a `RESULT:` line; scripts in `api/scripts/` own exit codes. `sqlc`, `openapi-lint`, `seed` exit 2 until BE-02 / BE-01 / SEED-01 (`unavailable.sh`): replace them when the input exists.
- `api/tools/testsummary` summarises `go test -json`; goose runs via `go run ...goose/v3@v3.30.1` (not in go.mod).
- Integration tests: `//go:build integration`; `test-integration` brings up Docker db, creates/migrates `wuppa_test`, exports DATABASE_URL; use `testenv.DatabaseURL(t)`.
- `make ci` is what CI runs; CI uses docker compose (no postgres service).
- Do not run `test-selftest.sh` concurrently with other test targets. Makefile `.env` include overrides env vars: pass DATABASE_URL on the make command line.
- docker-compose ports are bound to 127.0.0.1.
