# SET-01 · review (fast, 1 round, reviewer-claude)

| # | Severity | Where | Status | Resolution |
| --- | --- | --- | --- | --- |
| 1 | minor | api/Makefile:11 | ACCEPTED, documented | make maps any failed recipe to exit 2; exact 0/1/2 live in api/scripts/lint.sh. Recorded in docs/decisions.md; SET-02 should follow the same pattern. |
| 2 | minor | api/scripts/lint-selftest.sh | FIXED | api/internal/zzlintselftest/ added to .gitignore |
| 3 | minor | .github/workflows/api.yml:12 | FIXED | paths now include .github/workflows/** |
