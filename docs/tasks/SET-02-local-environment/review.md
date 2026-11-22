# SET-02 · review

Level standard. reviewer-claude: 1 round. reviewer-codex: **did not run** (stuck at Codex's own "Trust this folder" prompt; no reply from the orchestrator to QUESTION 1/2, so the trust decision was not taken). Cross-exchange skipped.

| # | Severity | Location | Finding | Status | Resolution |
| --- | --- | --- | --- | --- | --- |
| 1 | critical | api/tools/testsummary/summary.go | Parent test failing by itself while subtests pass gave PASS / exit 0 | ACCEPTED (reproduced) | fixed test-first: fixtures `parent_failure`, `package_fail`; failed parent reported; package fallback |
| 2 | major | api/scripts/test-selftest.sh (check 15) | migrate-down ran against the dev database | ACCEPTED | check 15 runs against `wuppa_test` |
| 3 | minor | api/scripts/test.sh | go test non-zero exit ignored when summary says PASS | ACCEPTED | now `RESULT: ERROR ... go test exited <n>`, exit 2 (no selftest check) |
| 4 | minor | api/docker-compose.yml | ports bound to all interfaces | ACCEPTED | bound to 127.0.0.1 |
| 5 | minor | api/scripts/lint.sh | integration-tagged files not linted | ACCEPTED | `--build-tags integration` |
| 6 | minor | api/scripts/migrate.sh | `down` PASS line reports total migrations | follow-up | cosmetic |
