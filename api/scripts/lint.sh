#!/usr/bin/env bash
# Agent-friendly golangci-lint wrapper. Exit 0 pass, 1 findings, 2 environment error.
# The last stdout line is always a RESULT line.
set -u

cd "$(dirname "${BASH_SOURCE[0]}")/.." || { echo "RESULT: ERROR lint cannot enter api dir"; exit 2; }
out=.out
log="$out/lint.log"
mkdir -p "$out"

if ! command -v golangci-lint >/dev/null 2>&1; then
  echo "RESULT: ERROR lint golangci-lint not found (install v2.15)"
  exit 2
fi

NO_COLOR=1 golangci-lint run --timeout 5m ./... >"$log" 2>&1
code=$?
if [ "$code" -eq 0 ]; then
  echo "RESULT: PASS lint issues=0"
  exit 0
fi

pattern='^[^ :]+:[0-9]+:[0-9]+: .+ \([a-z0-9_-]+\)$'
issues=$(grep -Ec "$pattern" "$log")
if [ "$code" -eq 1 ] && [ "$issues" -gt 0 ]; then
  grep -E "$pattern" "$log" | head -n 60
  echo "RESULT: FAIL lint issues=$issues log=$log"
  exit 1
fi

head -n 20 "$log"
echo "RESULT: ERROR lint golangci-lint exited $code (see $log)"
exit 2
