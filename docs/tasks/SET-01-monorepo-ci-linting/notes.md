# SET-01 · notes from the orchestrator

Decisions for this step (they close gaps in the spec; follow them):

1. **Make targets that do not exist yet.** SET-02 builds the real Makefile. In SET-01, create `api/Makefile` with only
   `lint` (and `ci`). CI calls `make ci`; in SET-01 `ci` runs `lint` only. SET-02 will extend `ci` to
   lint + sqlc diff check + migrate + test. Do not add stub targets that pretend to pass.
2. **`make lint` follows the agent-friendly contract** in `CLAUDE.md` ("Step workflow"): full output in `api/.out/lint.log`,
   findings one per line `file:line:col: message (linter)` (max 60), last line `RESULT: PASS lint issues=0` /
   `RESULT: FAIL lint issues=<n> log=<path>` / `RESULT: ERROR lint <reason>` (e.g. golangci-lint missing), exit 0 / 1 / 2.
3. **Lint needs Go code.** Create `api/go.mod` (module `github.com/VlasovArtem/wuppa/api`, `go 1.23`) and a minimal
   `api/cmd/api/main.go` placeholder (package main, prints nothing important; BE-01 replaces it).
4. **golangci-lint is v2 locally (2.15.0)**: `api/.golangci.yml` must use the v2 format (`version: "2"`). Pin the same
   major in CI (`golangci/golangci-lint-action` with `version: v2.15`). `staticcheck` in v2 is a linter in `linters.enable`.
5. **app/ is empty until SET-03.** Create `app/.gitkeep`. In `app.yml`, guard the Flutter steps with
   `if: hashFiles('app/pubspec.yaml') != ''` so the workflow passes until SET-03. Flutter is **not installed locally**
   (tell the orchestrator in result.md follow-ups; SET-03 needs it).
6. **Workflows:** `api.yml` with `paths: ['api/**', '.github/workflows/api.yml']`, Go from `api/go.mod`
   (`actions/setup-go` with `go-version-file`), a `postgres:16` service (user/password/db `wuppa`, health check) even
   though only lint runs now, then `make -C api ci`. Same `paths` pattern for `app.yml`.
7. **Tests for this step (RED first):**
   - a lint self-test script `api/scripts/lint-selftest.sh` that copies a deliberately bad file (e.g. an unchecked
     error) into a temp package, runs `make -C api lint`, expects exit 1, a `file:line` finding and a `RESULT: FAIL`
     line, then removes the file (trap). RED = the script fails before the Makefile/config exist.
   - workflow validation with actionlint, run without installing it: `go run github.com/rhysd/actionlint/cmd/actionlint@v1.7.7`
     (make target `lint-workflows` at repo root is not needed; put the command in `api/Makefile` as `lint-workflows` with the
     same RESULT contract, and call it from `ci`).
8. **Root files:** extend the existing `.gitignore` (keep `.idea`, `.steps/`, `.out/`; add Go, Flutter, IDE, `.env`, `api/.out/`,
   `app/.out/`). `README.md`: what Wuppa is in two lines, layout, how to run lint, link to `docs/poc-plan.md`.
   Delete `main.go`, `go.mod`, `gitignore.gitignore` at the root (the untracked `gitignore` file too if present).
9. Runner commands: `make -C api lint`, `make -C api lint-workflows`, `bash api/scripts/lint-selftest.sh`.
