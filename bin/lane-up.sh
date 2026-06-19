#!/usr/bin/env bash
# Boot a lane's stack via the active profile's boot + health hooks.
#   lane-up.sh <N> [--no-build]   # --no-build reuses the existing FE build
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
require_lane "${1:-}"
N="$1"; BUILD=1; [ "${2:-}" == "--no-build" ] && BUILD=0
DIR="$(lane_dir "$N")"
[ -d "$DIR/.git" ] || die "lane $N not bootstrapped (run: lane-bootstrap.sh $N)"

# Defensive: stop any existing stack first so a re-run (e.g. dashboard ▶ up on a
# live lane) can't double-start services / fight over the lane's ports.
"$HARNESS_ROOT/bin/lane-down.sh" "$N" >/dev/null 2>&1 || true

mkdir -p "$(lane_run_dir "$N")" "$(lane_log_dir "$N")" "$(lane_upload_dir "$N")"
API_PORT="$(lane_api_port "$N")"; FE_PORT="$(lane_fe_port "$N")"

# Ensure backend/.env exists (seeded from the source repo's real .env, with the
# per-lane DATABASE_URL/REDIS_URL/UPLOAD_DIR written INTO the file).
"$HARNESS_ROOT/bin/lane-env-seed.sh" "$N" || echo "harness: WARNING — .env seed failed; run bin/lane-env-seed.sh $N"

"$HARNESS_ROOT/bin/state.sh" "$N" set stage=booting status=running
hb_start "$N"; trap hb_stop EXIT   # build may wait on the build-lock + compile

echo "harness: booting lane $N stack (profile: $PROFILE) ..."
if [ "$BUILD" == 1 ]; then run_hook "$N" boot; else run_hook "$N" boot --no-build; fi

if run_hook "$N" health; then
  "$HARNESS_ROOT/bin/state.sh" "$N" set stage=live status=running notes="api=:$API_PORT fe=:$FE_PORT"
  echo "harness: lane $N live -> $(lane_fe_url "$N")"
else
  "$HARNESS_ROOT/bin/state.sh" "$N" set stage=boot-failed status=failed \
    notes="health check failed; see logs/lane$N"
  die "lane $N failed to become healthy"
fi
