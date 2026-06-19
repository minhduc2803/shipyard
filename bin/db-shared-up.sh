#!/usr/bin/env bash
# Bring up the single shared Postgres+Redis+Adminer (source repo compose) and
# ensure each lane's database exists. Idempotent.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

echo "harness: starting shared postgres/redis/adminer..."
docker compose -f "$COMPOSE_FILE" up -d $COMPOSE_SERVICES

echo "harness: waiting for postgres on $PG_HOST:$PG_PORT..."
for _ in $(seq 1 30); do
  if docker compose -f "$COMPOSE_FILE" exec -T "$DB_SERVICE" pg_isready -U "$PG_USER" >/dev/null 2>&1; then
    ok=1; break
  fi
  sleep 1
done
[[ "${ok:-}" == 1 ]] || die "postgres never became ready"

LANES="$(discover_lanes)"; [ -n "$LANES" ] || LANES="1 2 3"   # first-time setup default
for n in $LANES; do
  db="$(lane_db "$n")"
  if docker compose -f "$COMPOSE_FILE" exec -T "$DB_SERVICE" \
       psql -U "$PG_USER" -tAc "SELECT 1 FROM pg_database WHERE datname='$db'" | grep -q 1; then
    echo "harness: db $db exists"
  else
    docker compose -f "$COMPOSE_FILE" exec -T "$DB_SERVICE" createdb -U "$PG_USER" "$db"
    echo "harness: created db $db"
  fi
done
echo "harness: shared services ready."
