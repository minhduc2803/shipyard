#!/usr/bin/env bash
# Front door: pick the next FREE lane, reserve it for a feature, boot its stack,
# and print the command to open a Claude session there and run /ship-feature.
#   lane-assign.sh "<feature title>" [--no-boot]
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
TITLE="${1:-}"; [ -n "$TITLE" ] || die "usage: lane-assign.sh \"<feature title>\" [--no-boot]"
BOOT=1; [ "${2:-}" == "--no-boot" ] && BOOT=0

# free = idle / down / no state file. (assigned/running/blocked/failed/passed = busy)
pick=""
for n in $(discover_lanes); do
  f="$(lane_state_file "$n")"
  st="idle"
  [ -f "$f" ] && st="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("status","idle"))' "$f" 2>/dev/null || echo idle)"
  case "$st" in idle|down|"") pick="$n"; break;; esac
done
[ -n "$pick" ] || die "no free lane (all busy). See bin/lane-status.sh; free one with bin/lane-reset.sh <N>, or provision another with bin/lane-add.sh."

echo "harness: assigning lane $pick -> \"$TITLE\""
"$HARNESS_ROOT/bin/state.sh" "$pick" set feature_title="$TITLE" stage=assigned status=assigned gate_decision=pending
if [ "$BOOT" = 1 ]; then
  echo "harness: booting lane $pick ..."
  "$HARNESS_ROOT/bin/lane-up.sh" "$pick"
fi

cat <<EOF

  ✅ Lane $pick reserved for: "$TITLE"
     manual-test URL: $(lane_fe_url "$pick")

  Open a Claude session in that lane and start the pipeline:

      cd $(lane_dir "$pick") && claude
      /ship-feature "$TITLE"

  Watch progress on the dashboard: bin/dashboard.sh -> http://127.0.0.1:8090
EOF
