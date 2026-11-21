#!/usr/bin/env bash
# Applies or rolls back goose migrations on DATABASE_URL.
# Usage: migrate.sh up | down   (down rolls back one migration)
# Exit 0 pass, 2 environment or migration error. The last stdout line is always a RESULT line.
set -u

GOOSE=github.com/pressly/goose/v3/cmd/goose@v3.30.1

cd "$(dirname "${BASH_SOURCE[0]}")/.." || { echo "RESULT: ERROR migrate cannot enter api dir"; exit 2; }
dir="${1:-}"
case "$dir" in
  up) target=migrate ;;
  down) target=migrate-down ;;
  *)
    echo "RESULT: ERROR migrate usage: migrate.sh up|down"
    exit 2
    ;;
esac
mkdir -p .out
log=".out/$target.log"

if [ -z "${DATABASE_URL:-}" ]; then
  echo "RESULT: ERROR $target DATABASE_URL is empty (copy .env.example to .env)"
  exit 2
fi

count=$(find migrations -maxdepth 1 -name '*.sql' 2>/dev/null | wc -l | tr -d ' ')
if [ "$count" -eq 0 ]; then
  echo "RESULT: PASS $target migrations=0"
  exit 0
fi

if ! NO_COLOR=1 go run "$GOOSE" -dir migrations postgres "$DATABASE_URL" "$dir" >"$log" 2>&1; then
  tail -n 20 "$log" | sed -E 's#(postgres(ql)?://)[^@ ]*@#\1***@#g'
  echo "RESULT: ERROR $target goose $dir failed (see api/$log)"
  exit 2
fi
echo "RESULT: PASS $target migrations=$count"
exit 0
