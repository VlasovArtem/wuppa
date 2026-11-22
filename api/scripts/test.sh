#!/usr/bin/env bash
# Agent-friendly go test wrapper. Usage: test.sh unit | integration
# Env: PKG (default ./...), RUN (go test -run pattern).
# Exit 0 pass, 1 test failure, 2 environment or usage error.
# The last stdout line is always a RESULT line (see CLAUDE.md, agent-friendly command contract).
set -u

cd "$(dirname "${BASH_SOURCE[0]}")/.." || { echo "RESULT: ERROR test cannot enter api dir"; exit 2; }
mode="${1:-}"
case "$mode" in
  unit) target=test-unit ;;
  integration) target=test-integration ;;
  *)
    echo "RESULT: ERROR test usage: test.sh unit|integration"
    exit 2
    ;;
esac
out=.out
mkdir -p "$out"
export NO_COLOR=1
pkg="${PKG:-./...}"
run="${RUN:-}"
log="$out/$target.log"
json="$out/$target.json"

if ! command -v go >/dev/null 2>&1; then
  echo "RESULT: ERROR $target go not found"
  exit 2
fi

# resolve PKG; an unknown or empty pattern is an environment/usage error
# shellcheck disable=SC2086
if ! listing=$(go list -e -f '{{.ImportPath}} {{len .TestGoFiles}} {{len .XTestGoFiles}} {{if .Error}}ERR{{end}}' $pkg 2>"$out/$target.list.err"); then
  head -n 10 "$out/$target.list.err"
  echo "RESULT: ERROR $target cannot list packages for PKG=$pkg"
  exit 2
fi
if [ -z "$listing" ] || echo "$listing" | grep -q ' ERR$'; then
  head -n 10 "$out/$target.list.err"
  echo "$listing" | grep ' ERR$' | head -n 5
  echo "RESULT: ERROR $target PKG=$pkg matched no valid packages"
  exit 2
fi

flags=(-json -count=1 -timeout 5m)
pkgs=("$pkg")
if [ "$mode" = integration ]; then
  # only packages that gain test files under the integration tag
  # shellcheck disable=SC2086
  tagged=$(go list -e -tags integration -f '{{.ImportPath}} {{len .TestGoFiles}} {{len .XTestGoFiles}}' $pkg 2>/dev/null)
  pkgs=()
  while IFS= read -r p; do
    [ -n "$p" ] && pkgs+=("$p")
  done < <(
    awk 'NR==FNR { base[$1] = $2 + $3; next } ($2 + $3) > (base[$1] + 0) { print $1 }' \
      <(echo "$listing") <(echo "$tagged")
  )
  if [ "${#pkgs[@]}" -eq 0 ]; then
    : >"$log"
    echo "RESULT: PASS $target tests=0 skipped=0 duration=0.0s"
    exit 0
  fi
  flags+=(-tags integration -p 1)

  if ! prep=$(bash scripts/db.sh ensure-test-db); then
    echo "$prep"
    echo "RESULT: ERROR $target database is not available"
    exit 2
  fi
  export DATABASE_URL='postgres://wuppa:wuppa@localhost:5432/wuppa_test?sslmode=disable'
  if ! prep=$(bash scripts/migrate.sh up); then
    echo "$prep"
    echo "RESULT: ERROR $target migrating wuppa_test failed"
    exit 2
  fi
fi
[ -n "$run" ] && flags+=(-run "$run")

if ! go build -o "$out/testsummary" ./tools/testsummary 2>"$out/$target.build.err"; then
  head -n 20 "$out/$target.build.err"
  echo "RESULT: ERROR $target cannot build tools/testsummary"
  exit 2
fi

go test "${flags[@]}" "${pkgs[@]}" >"$json" 2>&1
gocode=$?
summary=$("$out/testsummary" -target "$target" -log "$log" <"$json")
code=$?
if [ "$code" -eq 0 ] && [ "$gocode" -ne 0 ]; then
  # go test failed but the summary saw nothing wrong: never report a pass
  echo "RESULT: ERROR $target go test exited $gocode (see $log)"
  exit 2
fi
printf '%s\n' "$summary"
exit "$code"
