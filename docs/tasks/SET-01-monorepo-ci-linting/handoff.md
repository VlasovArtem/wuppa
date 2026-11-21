# SET-01 · handoff

- `api/Makefile`: targets lint, lint-workflows, lint-selftest, ci. `ci` is what CI runs; SET-02 extends it.
- Exact exit codes (0/1/2) come from scripts (`api/scripts/lint.sh`); make itself exits 2 on any failure. Use that pattern (script owns contract, last stdout line RESULT).
- Selftest creates `api/internal/zzlintselftest` temporarily (gitignored); do not run lint concurrently with it.
- app.yml Flutter steps are guarded by `hashFiles('app/pubspec.yaml')`; SET-03 removes the placeholder step.
- actionlint runs via `go run ...@v1.7.7` (needs network on first run).
