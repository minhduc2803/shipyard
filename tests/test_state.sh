#!/usr/bin/env bash
# state.sh: per-feature state, slug sanitization, stage timing, concurrency.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
setup_temp_harness; trap teardown_temp_harness EXIT

SD="$HARNESS_ROOT/state/lane3"

# --- init -------------------------------------------------------------------
st 3 init >/dev/null
assert_file "$SD/_pending.json" "init writes _pending.json"
assert_eq "" "$(cat "$SD/.active")" "init leaves .active empty"
assert_ne "" "$(st 3 get stage_since)" "init seeds stage_since"

# --- set merges keys + bumps heartbeat -------------------------------------
st 3 set feature_title="CSV export" stage=intake >/dev/null
assert_eq "CSV export" "$(st 3 get feature_title)" "set persists feature_title"
assert_ne "" "$(st 3 get last_heartbeat)" "set bumps last_heartbeat"

# --- stage_since: moves on stage change, stable otherwise -------------------
st 3 set stage=qc >/dev/null
SS1="$(st 3 get stage_since)"
st 3 set >/dev/null                 # bare heartbeat
st 3 set status=running >/dev/null  # same-stage set
assert_eq "$SS1" "$(st 3 get stage_since)" "stage_since stable on heartbeat/same-stage"
st 3 set stage=gate >/dev/null
assert_ne "$SS1" "$(st 3 get stage_since)" "stage_since moves on stage change"

# --- activate: renames _pending -> <slug>.json, sets .active, echoes slug ---
st 3 init >/dev/null
st 3 set feature_title="Feature A" >/dev/null   # lands in _pending
OUT="$(st 3 activate feat/feature-a)"
assert_eq "feature-a" "$OUT" "activate echoes canonical slug"
assert_eq "feature-a" "$(cat "$SD/.active")" "activate sets .active"
assert_file "$SD/feature-a.json" "activate renames _pending -> <slug>.json"
assert_eq "Feature A" "$(st 3 get feature_title)" "Stage-0 data survives activate"

# --- activate sanitizes slashes + spaces to single-segment -----------------
st 3 init >/dev/null
OUT="$(st 3 activate 'feat/foo/bar baz')"
assert_eq "foo-bar-baz" "$OUT" "activate sanitizes / and space to -"
assert_file "$SD/foo-bar-baz.json" "sanitized slug -> flat state file (no nested dir)"

# --- clear -> new feature flow (init resets the slot, preserves old) --------
st 3 init >/dev/null; st 3 set feature_title="First" >/dev/null; st 3 activate first >/dev/null
st 3 init >/dev/null                         # the dashboard "clear"
assert_eq "" "$(cat "$SD/.active")" "clear (init) resets .active"
assert_file "$SD/first.json" "clear preserves the previous feature's state file"
st 3 set feature_title="Second" >/dev/null; st 3 activate second >/dev/null
assert_eq "Second" "$(st 3 get feature_title)" "new feature is active after clear"
assert_eq "First" "$(python3 -c 'import json;print(json.load(open(__import__("sys").argv[1]))["feature_title"])' "$SD/first.json")" "old feature untouched"

# --- concurrency: flock prevents lost updates ------------------------------
st 3 init >/dev/null; st 3 set stage=qc >/dev/null
for i in $(seq 1 15); do st 3 set >/dev/null & done   # heartbeat storm
st 3 set qc_dev=passed >/dev/null &                   # the value that must survive
for i in $(seq 1 15); do st 3 set >/dev/null & done
wait
assert_eq "passed" "$(st 3 get qc_dev)" "concurrent writers do not lose qc_dev=passed"

finish
