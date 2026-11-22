#!/usr/bin/env bash
# Targets whose input does not exist yet. Usage: unavailable.sh <target> <task> <missing-file>
# Always exit 2 with a RESULT: ERROR line; no fake passes.
set -u

cd "$(dirname "${BASH_SOURCE[0]}")/.." || { echo "RESULT: ERROR ${1:-unknown} cannot enter api dir"; exit 2; }
target="${1:?target}"
task="${2:?task}"
missing="${3:?missing file}"

if [ -e "$missing" ]; then
  echo "RESULT: ERROR $target $missing exists but the target is not wired yet (see $task)"
else
  echo "RESULT: ERROR $target not available until $task ($missing)"
fi
exit 2
