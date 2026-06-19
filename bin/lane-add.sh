#!/usr/bin/env bash
# Provision a brand-new lane in the next free slot (1-9): clone + deps +
# migrate + seed. Writes state so the dashboard shows progress.
#   lane-add.sh [--and-up]      # --and-up also boots the stack afterwards
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
AND_UP=0; [ "${1:-}" == "--and-up" ] && AND_UP=1

N=""
for n in 1 2 3 4 5 6 7 8 9; do
  [ ! -d "$LANES_ROOT/lane$n" ] && { N="$n"; break; }
done
[ -n "$N" ] || die "all lane slots 1-9 are occupied"

echo "harness: provisioning new lane $N at $(lane_dir "$N") ..."
"$HARNESS_ROOT/bin/state.sh" "$N" init >/dev/null
# status=provisioning (a dedicated loading state — the dashboard shows a spinner
# and does NOT present the lane as ready until bootstrap fully finishes).
"$HARNESS_ROOT/bin/state.sh" "$N" set stage=provisioning status=provisioning \
  feature_title="(provisioning new lane…)" notes="setting up clone, deps, DB, MCPs, agents, sessions" >/dev/null

# HARNESS_PROVISION_STATE=1 makes bootstrap emit per-step progress to the state.
# LANE_DEV_QC_EMAIL/PASSWORD (when passed by the dashboard add modal) flow through
# to lane-qa-creds so the new lane's dev-QC account is set non-interactively.
if HARNESS_PROVISION_STATE=1 "$HARNESS_ROOT/bin/lane-bootstrap.sh" "$N"; then
  if [ "$AND_UP" == 1 ]; then
    "$HARNESS_ROOT/bin/state.sh" "$N" set stage=provisioning status=provisioning notes="booting stack" >/dev/null
    "$HARNESS_ROOT/bin/lane-up.sh" "$N"
  fi
  "$HARNESS_ROOT/bin/state.sh" "$N" init >/dev/null   # clean idle = READY (only now)
  echo "harness: lane $N ready -> $(lane_fe_url "$N")  (clone: $(lane_dir "$N"))"
else
  "$HARNESS_ROOT/bin/state.sh" "$N" set stage=bootstrap-failed status=failed \
    notes="bootstrap failed; see logs/dashboard-actions.log" >/dev/null
  die "lane $N bootstrap failed"
fi
