#!/usr/bin/env bash
# Spec stage 5 (automated part): run Playwright e2e against the lane's RUNNING
# integrated stack, under e2e.lock. Expects the stack already up (via
# lane-integrate) — ideally booted with MOCK_AGENT=true so specs that touch the
# agent get canned responses. Writes lane state.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
require_lane "${1:-}"
N="$1"; DIR="$(lane_dir "$N")"
[ -d "$DIR/.git" ] || die "lane $N not bootstrapped"

"$HARNESS_ROOT/bin/state.sh" "$N" set stage=e2e status=running
hb_start "$N"; trap hb_stop EXIT   # e2e can run many minutes (incl. lock wait)
echo "harness: running e2e (profile hook) ..."
run_hook "$N" e2e
"$HARNESS_ROOT/bin/state.sh" "$N" set stage=e2e-passed status=running
echo "harness: lane $N — e2e passed."
