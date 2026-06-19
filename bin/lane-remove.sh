#!/usr/bin/env bash
# Remove a lane COMPLETELY: stop its stack, drop its databases, delete the
# clone, and clear all harness state for it. Destructive — no undo.
#   lane-remove.sh <N>
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
require_lane "${1:-}"
N="$1"; DIR="$(lane_dir "$N")"
case "$DIR" in */lane$N) ;; *) die "refusing: unexpected lane dir '$DIR'";; esac

echo "harness: removing lane $N ..."
"$HARNESS_ROOT/bin/state.sh" "$N" set stage=removing status=running >/dev/null 2>&1 || true
"$HARNESS_ROOT/bin/lane-down.sh" "$N" >/dev/null 2>&1 || true

for db in "$(lane_db "$N")" "$(lane_db "$N")_test"; do
  docker compose -f "$COMPOSE_FILE" exec -T "$DB_SERVICE" \
    dropdb --if-exists -U "$PG_USER" "$db" 2>/dev/null || true
done

[ -d "$DIR" ] && rm -rf "$DIR"
rm -rf "$HARNESS_ROOT/state/lane$N" "$HARNESS_ROOT/state/lane$N.json" "$HARNESS_ROOT/state/lane$N.pr-cursor"
rm -rf "$(lane_run_dir "$N")" "$(lane_log_dir "$N")"
echo "harness: lane $N removed (clone, DBs, state, logs)."
