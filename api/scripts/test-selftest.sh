#!/usr/bin/env bash
# Self-test for the local environment and test targets (SET-02).
# Checks 11-15 of the plan: failing test, passing test, unknown PKG,
# test-integration with the db stopped, migrate / migrate-down / migrate.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
api="$(cd "$here/.." && pwd)"
cd "$api" || exit 2
fails=0
tmpdir="$api/internal/zztestselftest"
out="$(mktemp)"

cleanup() {
  rm -rf "$tmpdir" "$out"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*"
  fails=$((fails + 1))
}

last_line() { tail -n 1 "$out"; }

mkdir -p "$tmpdir"
printf 'package zztestselftest\n' >"$tmpdir/zz.go"

# 11: failing temp test
cat >"$tmpdir/zz_test.go" <<'EOF'
package zztestselftest

import "testing"

func TestZZ(t *testing.T) {
	t.Errorf("deliberate failure")
}
EOF
PKG=./internal/zztestselftest/... bash scripts/test.sh unit >"$out" 2>&1
code=$?
[ "$code" -eq 1 ] || fail "11 failing test: exit $code, expected 1"
grep -Eq '^FAIL .*TestZZ \(zz_test\.go:[0-9]+\)$' "$out" || fail "11 failing test: no 'FAIL ... TestZZ (zz_test.go:<n>)' line"
grep -q 'deliberate failure' "$out" || fail "11 failing test: message line missing"
last_line | grep -Eq '^RESULT: FAIL test-unit failed=1 log=' || fail "11 failing test: last line is '$(last_line)'"

# 12: passing temp test
cat >"$tmpdir/zz_test.go" <<'EOF'
package zztestselftest

import "testing"

func TestZZ(t *testing.T) {}
EOF
PKG=./internal/zztestselftest/... bash scripts/test.sh unit >"$out" 2>&1
code=$?
[ "$code" -eq 0 ] || fail "12 passing test: exit $code, expected 0"
last_line | grep -Eq '^RESULT: PASS test-unit tests=1 ' || fail "12 passing test: last line is '$(last_line)'"

# 13: unknown PKG
PKG=./nope/... bash scripts/test.sh unit >"$out" 2>&1
code=$?
[ "$code" -eq 2 ] || fail "13 unknown PKG: exit $code, expected 2"
last_line | grep -Eq '^RESULT: ERROR test-unit ' || fail "13 unknown PKG: last line is '$(last_line)'"

# 14: db stopped, make test-integration starts it itself
if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  fail "14 docker is not available"
else
  docker compose stop db >/dev/null 2>&1
  make --no-print-directory test-integration >"$out" 2>&1
  code=$?
  [ "$code" -eq 0 ] || fail "14 test-integration: exit $code, expected 0"
  last_line | grep -Eq '^RESULT: PASS test-integration tests=1 ' || fail "14 test-integration: last line is '$(last_line)'"
  health="$(docker inspect -f '{{.State.Health.Status}}' "$(docker compose ps -q db)" 2>/dev/null)"
  [ "$health" = "healthy" ] || fail "14 db is '$health' afterwards, expected healthy"
  docker compose exec -T db psql -U wuppa -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='wuppa_test'" 2>/dev/null | grep -q 1 ||
    fail "14 database wuppa_test does not exist"

  # 15: migrate / migrate-down / migrate
  # always against wuppa_test, never the developer database
  testdb='postgres://wuppa:wuppa@localhost:5432/wuppa_test?sslmode=disable'
  for tgt in migrate migrate-down migrate; do
    make --no-print-directory "$tgt" "DATABASE_URL=$testdb" >"$out" 2>&1
    code=$?
    [ "$code" -eq 0 ] || fail "15 make $tgt: exit $code, expected 0"
    last_line | grep -Eq '^RESULT: PASS ' || fail "15 make $tgt: last line is '$(last_line)'"
  done
fi

if [ "$fails" -eq 0 ]; then
  echo "test-selftest: PASS"
  exit 0
fi
echo "test-selftest: FAIL failures=$fails"
exit 1
