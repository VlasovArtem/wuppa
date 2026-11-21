#!/usr/bin/env bash
# Local database stack (PostgreSQL 16 + Mailpit) via Docker Compose.
# Usage: db.sh up | down | ensure-test-db
# Exit 0 pass, 2 environment error. The last stdout line is always a RESULT line.
set -u

cd "$(dirname "${BASH_SOURCE[0]}")/.." || { echo "RESULT: ERROR db cannot enter api dir"; exit 2; }
cmd="${1:-}"
target="db-$cmd"
[ "$cmd" = "ensure-test-db" ] && target="ensure-test-db"
mkdir -p .out
log=".out/$target.log"

err() {
  echo "RESULT: ERROR $target $*"
  exit 2
}

need_docker() {
  command -v docker >/dev/null 2>&1 || err "docker not found (install Docker)"
  docker info >/dev/null 2>&1 || err "docker is not running (start Docker)"
  docker compose version >/dev/null 2>&1 || err "docker compose plugin not found"
}

port_busy() {
  (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
}

# up_services <service...>: start services and wait until healthy.
up_services() {
  if [ -z "$(docker compose ps -q --status running db 2>/dev/null)" ] && port_busy 5432; then
    err "port 5432 is busy (stop the local PostgreSQL or the process using it)"
  fi
  if ! docker compose up -d --wait "$@" >"$log" 2>&1; then
    tail -n 20 "$log"
    err "docker compose up failed (see api/$log)"
  fi
}

case "$cmd" in
  up)
    need_docker
    up_services db mailpit
    echo "RESULT: PASS db-up services=db,mailpit"
    ;;
  down)
    need_docker
    if ! docker compose down >"$log" 2>&1; then
      tail -n 20 "$log"
      err "docker compose down failed (see api/$log)"
    fi
    echo "RESULT: PASS db-down"
    ;;
  ensure-test-db)
    need_docker
    up_services db
    exists=$(docker compose exec -T db psql -U wuppa -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='wuppa_test'" 2>>"$log")
    if [ "$exists" != "1" ]; then
      if ! docker compose exec -T db psql -U wuppa -d postgres -c "CREATE DATABASE wuppa_test" >>"$log" 2>&1; then
        tail -n 20 "$log"
        err "cannot create database wuppa_test (see api/$log)"
      fi
    fi
    echo "RESULT: PASS ensure-test-db database=wuppa_test"
    ;;
  *)
    echo "RESULT: ERROR db usage: db.sh up|down|ensure-test-db"
    exit 2
    ;;
esac
