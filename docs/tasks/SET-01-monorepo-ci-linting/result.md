# SET-01 · result

status: DONE
pr: 'https://github.com/VlasovArtem/wuppa/pull/37'
commits: 711da8a test(SET-01): failing tests; fdaddb4 SET-01: monorepo skeleton, lint, workflows; plus review fixes and docs

## Gates

- RED: selftest exit 1 with 7 failing checks; `make -C api lint-workflows` exit 2 (no target). No pre-existing tests.
- GREEN: `RESULT: PASS lint issues=0`; `RESULT: PASS lint-workflows issues=0`; `lint-selftest: PASS`; `make -C api ci` exit 0. No unit/integration targets exist yet (SET-02).

## Review

Level fast, 1 round. Accepted: 3 minor (2 fixed, 1 documented). Dropped: 0.

## Deviations from the plan

- `make` exits 2 on any failed recipe, so the 0/1/2 contract is implemented in `api/scripts/lint.sh`; `make lint` wraps it (approved TEST-CHANGE).
- `ci` also runs lint-selftest (orchestrator request). api.yml paths include `.github/workflows/**`.

## Open manual checks

- None. CI verified on GitHub: `gh pr checks 37` green (api ci 1m55s, app ci 5s). The first run failed because golangci-lint-action ran its own lint at the repo root; fixed by installing the binary with `go install ...@v2.15.0`.

## Follow-ups

- Flutter is not installed locally; SET-03 needs it.
- SET-02: extend `ci` (sqlc diff, migrate, test); keep scripts-own-exit-codes pattern.
