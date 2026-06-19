#!/usr/bin/env bash
# _common.sh: per-lane path resolution + the .harness-lane marker.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
setup_temp_harness; trap teardown_temp_harness EXIT

# shellcheck disable=SC1091
source "$REPO/bin/_common.sh"

# --- lane_state_file resolves via .active ----------------------------------
SD="$HARNESS_ROOT/state/lane4"; mkdir -p "$SD"
printf '' > "$SD/.active"
assert_eq "$SD/_pending.json" "$(lane_state_file 4)" "empty .active -> _pending.json"
printf 'my-feat' > "$SD/.active"
assert_eq "$SD/my-feat.json" "$(lane_state_file 4)" ".active=my-feat -> my-feat.json"

# --- derived per-lane values ------------------------------------------------
assert_eq "8004" "$(lane_api_port 4)" "lane_api_port derives from API_BASE_PORT"
assert_eq "3004" "$(lane_fe_port 4)"  "lane_fe_port derives from FE_BASE_PORT"
assert_eq "edc_test_l4" "$(lane_db 4)" "lane_db derives from DB_PREFIX"

# --- write_lane_markers writes .harness-lane + git-excludes it --------------
LD="$LANES_ROOT/lane4"; mkdir -p "$LD/.git/info"
write_lane_markers 4 "$LD"
assert_eq "4" "$(cat "$LD/.harness-lane")" ".harness-lane = lane number"
assert_contains "$(cat "$LD/.git/info/exclude")" ".harness-lane" ".harness-lane is git-excluded"
assert_contains "$(cat "$LD/.git/info/exclude")" "/proof" "stray root proof is git-excluded"
# idempotent: second call doesn't duplicate the exclude entry
write_lane_markers 4 "$LD"
assert_eq "1" "$(grep -c '^.harness-lane$' "$LD/.git/info/exclude")" "exclude entry not duplicated on re-run"

# --- ensure_proof_link: clone-root proof converges onto the canonical root -------
# write_lane_markers above already linked a fresh lane (no prior proof/):
assert_eq ".playwright-mcp/proof" "$(readlink "$LD/proof" 2>/dev/null)" "fresh lane: proof -> .playwright-mcp/proof symlink"
# a write through the symlink lands in the canonical root the dashboard reads:
mkdir -p "$LD/proof/f/qc-local"; printf x > "$LD/proof/f/qc-local/1.png"
assert_file "$LD/.playwright-mcp/proof/f/qc-local/1.png" "write via proof/ symlink lands in .playwright-mcp/proof"

# a pre-existing REAL proof/ dir (older lane) is migrated into canonical, then linked:
ML="$LANES_ROOT/lane5"; mkdir -p "$ML/proof/feat/ticket" "$ML/.playwright-mcp/proof/feat/qc-local"
printf 'r' > "$ML/proof/feat/ticket/REPORT.html"
printf 'l' > "$ML/.playwright-mcp/proof/feat/qc-local/01.png"
ensure_proof_link "$ML"
assert_eq ".playwright-mcp/proof" "$(readlink "$ML/proof" 2>/dev/null)" "real proof/ dir replaced by a symlink"
assert_file "$ML/.playwright-mcp/proof/feat/ticket/REPORT.html" "stranded ticket migrated to the canonical root"
assert_file "$ML/.playwright-mcp/proof/feat/qc-local/01.png" "existing canonical proof preserved through migration"

finish
