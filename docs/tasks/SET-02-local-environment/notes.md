# SET-02 · notes from the orchestrator

- `go test -json` (Go 1.24+) reports build failures as JSON events with `"Action":"build-output"` / `"build-fail"` and an `ImportPath`;
  test events carry `Package`, `Test`, `Action` (run/pass/fail/skip/output), `Output`, `Time`, `Elapsed`. Capture fixtures from real runs
  (write a throwaway failing package, run `go test -json`, save to `testdata/`, delete the package).
- A pattern that matches nothing (`./nope/...`) makes `go test` exit 1 with a plain-text error on stderr and no JSON events:
  `test.sh` must keep stderr apart and turn "no events + stderr" into `RESULT: ERROR`, exit 2.
- `docker compose up -d --wait` waits for health checks (Compose v2). GitHub's ubuntu runners have Compose v2.
- Local tools: go 1.27.4, golangci-lint 2.15.0, docker. No goose/sqlc binaries installed (hence `go run`).
- Lint runs over `./...`, so testsummary and testenv must be lint-clean (errcheck, gosec, revive).
