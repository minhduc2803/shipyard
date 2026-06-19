#!/usr/bin/env bash
# Pre-push CI gates on the lane's CURRENT branch (spec stage 2): runs the active
# profile's ci-gate hook (the app's own lint / test / contract checks).
# Uses an isolated, freshly-recreated per-lane test DB so it never touches the
# lane's working DB. Writes lane state. Exits non-zero on first failure.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
require_lane "${1:-}"
N="$1"; DIR="$(lane_dir "$N")"
[ -d "$DIR/.git" ] || die "lane $N not bootstrapped"
TEST_DB="$(lane_db "$N")_test"
TEST_DB_URL="${DB_URL_SCHEME}://$PG_USER:$PG_PASS@$PG_HOST:$PG_PORT/$TEST_DB"

"$HARNESS_ROOT/bin/state.sh" "$N" set stage=pre-push-gate status=running ci_status=running
hb_start "$N"; trap hb_stop EXIT   # keep heartbeat fresh through the long gates

echo "harness: recreating isolated test DB $TEST_DB ..."
docker compose -f "$COMPOSE_FILE" exec -T "$DB_SERVICE" dropdb --if-exists -U "$PG_USER" "$TEST_DB" >/dev/null
docker compose -f "$COMPOSE_FILE" exec -T "$DB_SERVICE" createdb -U "$PG_USER" "$TEST_DB" >/dev/null

echo "harness: running CI gates (profile hook) ..."
export TEST_DATABASE_URL="$TEST_DB_URL"
run_hook "$N" ci-gate

"$HARNESS_ROOT/bin/state.sh" "$N" set stage=pre-push-gate status=running ci_status=local-gates-green
echo "harness: lane $N — pre-push CI gates GREEN."
