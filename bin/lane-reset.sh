#!/usr/bin/env bash
# Reset a lane clone to a clean development checkout and a fresh DB seed,
# so the next feature starts from a known state. Stops the lane first.
#   lane-reset.sh <N> [--keep-db]   # --keep-db skips the DB re-seed
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
require_lane "${1:-}"
N="$1"; KEEPDB=0; [ "${2:-}" == "--keep-db" ] && KEEPDB=1
DIR="$(lane_dir "$N")"
[ -d "$DIR/.git" ] || die "lane $N not bootstrapped"

"$HARNESS_ROOT/bin/lane-down.sh" "$N" || true

echo "harness: resetting git to origin/development ..."
git -C "$DIR" fetch origin --prune
CUR="$(git -C "$DIR" rev-parse --abbrev-ref HEAD)"
git -C "$DIR" checkout "$INTEGRATION_BRANCH" 2>/dev/null || git -C "$DIR" checkout -b "$INTEGRATION_BRANCH" "origin/$INTEGRATION_BRANCH"
git -C "$DIR" reset --hard "origin/$INTEGRATION_BRANCH"
# remove untracked non-ignored files (stray/uncommitted feature files); deps,
# .env and data/uploads are gitignored so they survive (-x NOT used on purpose).
git -C "$DIR" clean -fd 2>/dev/null || true
# drop the feature branch the lane was on (if any, and not development/main)
if [[ -n "$CUR" && "$CUR" != "$INTEGRATION_BRANCH" && "$CUR" != "$BASE_BRANCH" && "$CUR" != "HEAD" ]]; then
  git -C "$DIR" branch -D "$CUR" 2>/dev/null || true
fi
write_lane_markers "$N" "$DIR"

echo "harness: clearing uploads ..."
rm -rf "$(lane_upload_dir "$N")"/* 2>/dev/null || true

if [ "$KEEPDB" == 0 ]; then
  echo "harness: recreating db $(lane_db "$N") ..."
  docker compose -f "$COMPOSE_FILE" exec -T "$DB_SERVICE" dropdb --if-exists -U "$PG_USER" "$(lane_db "$N")"
  docker compose -f "$COMPOSE_FILE" exec -T "$DB_SERVICE" createdb -U "$PG_USER" "$(lane_db "$N")"
  run_hook "$N" migrate
  run_hook "$N" seed
fi

rm -f "$HARNESS_ROOT/state/lane$N.pr-cursor" "$HARNESS_ROOT/state/lane$N"/*.pr-cursor 2>/dev/null   # next feature = new PR; drop comment cursors (flat + per-feature)
"$HARNESS_ROOT/bin/state.sh" "$N" init
echo "harness: lane $N reset to clean development."
