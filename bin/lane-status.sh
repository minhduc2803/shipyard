#!/usr/bin/env bash
# Print a compact status table for one lane (arg) or all lanes (no arg).
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

printf "%-5s %-10s %-9s %-24s %-22s %s\n" LANE STAGE STATUS BRANCH URL FEATURE
LANES="${1:-$(discover_lanes)}"; [ -n "$LANES" ] || { echo "(no lanes exist — bin/lane-add.sh to create one)"; exit 0; }
for n in $LANES; do
  f="$(lane_state_file "$n")"
  if [ -f "$f" ]; then
    python3 - "$f" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print("%-5s %-10s %-9s %-24s %-22s %s" % (
  d.get("lane",""), d.get("stage",""), d.get("status",""),
  (d.get("branch","") or "-")[:24], d.get("manual_test_url",""),
  d.get("feature_title","")))
PY
  else
    printf "%-5s %-10s %-9s %-24s %-22s %s\n" "$n" "no-state" "-" "-" "$(lane_fe_url "$n")" "-"
  fi
done
