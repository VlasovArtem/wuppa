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

- Workflows have not run on real GitHub Actions yet (golangci-lint-action@v8 install-only unverified); check the PR's checks.

## Follow-ups

- Flutter is not installed locally; SET-03 needs it.
- SET-02: extend `ci` (sqlc diff, migrate, test); keep scripts-own-exit-codes pattern.
