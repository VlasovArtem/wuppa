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

# --- clean tree passes ----------------------------------------------------
make -C "$api" lint >"$out" 2>&1
code=$?
last="$(tail -n 1 "$out")"
if [ "$code" -ne 0 ]; then
  fail "clean tree: make lint exited $code, expected 0"
fi
if [ "$last" != "RESULT: PASS lint issues=0" ]; then
  fail "clean tree: last line is '$last', expected 'RESULT: PASS lint issues=0'"
fi

# --- deliberate lint error fails ------------------------------------------
mkdir -p "$tmpdir"
cat >"$tmpdir/bad.go" <<'EOF'
package zzlintselftest

import "os"

func Bad() {
	os.Remove("/nonexistent/wuppa-selftest")
}
EOF

make -C "$api" lint >"$out" 2>&1
code=$?
last="$(tail -n 1 "$out")"
if [ "$code" -ne 1 ]; then
  fail "bad file: make lint exited $code, expected 1"
fi
if ! grep -Eq '^[^ :]+:[0-9]+:[0-9]+: .+ \([a-z]+\)$' "$out"; then
  fail "bad file: no 'file:line:col: message (linter)' line in output"
fi
if ! printf '%s\n' "$last" | grep -Eq '^RESULT: FAIL lint issues=[0-9]+ log=.+'; then
  fail "bad file: last line is '$last', expected 'RESULT: FAIL lint issues=<n> log=<path>'"
fi

if [ "$fails" -ne 0 ]; then
  echo "lint-selftest: FAIL ($fails checks failed)"
  exit 1
fi
echo "lint-selftest: PASS"
