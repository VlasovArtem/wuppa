#!/usr/bin/env bash
# Self-test for the lint setup (SET-01).
# Checks: workflows exist, a clean tree passes `make lint`, a deliberate lint error fails it.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
api="$(cd "$here/.." && pwd)"
root="$(cd "$api/.." && pwd)"
fails=0
tmpdir="$api/internal/zzlintselftest"
out="$(mktemp)"

cleanup() {
  rm -rf "$tmpdir" "$out"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*"
  fails=$((fails + 1))
}

# --- workflow files -------------------------------------------------------
for wf in api app; do
  f="$root/.github/workflows/$wf.yml"
  if [ ! -f "$f" ]; then
    fail "missing $f"
    continue
  fi
  grep -q "paths:" "$f" || fail "$wf.yml has no paths filter"
  grep -q "$wf/\*\*" "$f" || fail "$wf.yml paths filter does not contain $wf/**"
done
if [ -f "$root/.github/workflows/app.yml" ]; then
  grep -q "hashFiles('app/pubspec.yaml')" "$root/.github/workflows/app.yml" ||
    fail "app.yml has no hashFiles('app/pubspec.yaml') guard"
fi

# check_clean <label> <command...>: exit 0 and last stdout line RESULT: PASS
check_clean() {
  label="$1"; shift
  "$@" >"$out" 2>/dev/null
  code=$?
  last="$(tail -n 1 "$out")"
  [ "$code" -eq 0 ] || fail "$label clean tree: exit $code, expected 0"
  [ "$last" = "RESULT: PASS lint issues=0" ] ||
    fail "$label clean tree: last line is '$last', expected 'RESULT: PASS lint issues=0'"
}

# check_bad <label> <expected-exit|nonzero> <command...>
check_bad() {
  label="$1"; want="$2"; shift 2
  "$@" >"$out" 2>/dev/null
  code=$?
  last="$(tail -n 1 "$out")"
  if [ "$want" = "nonzero" ]; then
    [ "$code" -ne 0 ] || fail "$label bad file: exit 0, expected non-zero"
  else
    [ "$code" -eq "$want" ] || fail "$label bad file: exit $code, expected $want"
  fi
  grep -Eq '^[^ :]+:[0-9]+:[0-9]+: .+ \([a-z]+\)$' "$out" ||
    fail "$label bad file: no 'file:line:col: message (linter)' line"
  printf '%s\n' "$last" | grep -Eq '^RESULT: FAIL lint issues=[0-9]+ log=.+' ||
    fail "$label bad file: last line is '$last', expected 'RESULT: FAIL lint issues=<n> log=<path>'"
}

# --- clean tree passes ----------------------------------------------------
check_clean "scripts/lint.sh" bash "$api/scripts/lint.sh"
check_clean "make lint" make -s -C "$api" lint

# --- deliberate lint error fails ------------------------------------------
mkdir -p "$tmpdir"
cat >"$tmpdir/bad.go" <<'EOF'
package zzlintselftest

import "os"

func Bad() {
	os.Remove("/nonexistent/wuppa-selftest")
}
EOF

# The script owns the exact exit codes; make maps any recipe failure to exit 2.
check_bad "scripts/lint.sh" 1 bash "$api/scripts/lint.sh"
check_bad "make lint" nonzero make -s -C "$api" lint
rm -rf "$tmpdir"

if [ "$fails" -ne 0 ]; then
  echo "lint-selftest: FAIL ($fails checks failed)"
  exit 1
fi
echo "lint-selftest: PASS"
