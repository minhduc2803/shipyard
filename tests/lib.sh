#!/usr/bin/env bash
# Shared helpers for the harness's own test suite. Source from each test_*.sh.
#
# Isolation: each test runs the REAL bin/ scripts but against a TEMP HARNESS_ROOT
# (a throwaway dir with a minimal config/lanes.env), so state/proof writes never
# touch real lane state. state.sh resolves its state dir from $HARNESS_ROOT.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # real harness checkout
PASS=0; FAIL=0

# Build a throwaway harness root with just enough config for _common.sh + state.sh.
setup_temp_harness() {
  TMPH="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
  mkdir -p "$TMPH/config" "$TMPH/state" "$TMPH/lanes"
  cat > "$TMPH/config/lanes.env" <<EOF
HARNESS_ROOT="\${HARNESS_ROOT:-$TMPH}"
LANES_ROOT="\${LANES_ROOT:-$TMPH/lanes}"
PG_HOST=127.0.0.1
PG_PORT=5433
PG_USER=postgres
PG_PASS=postgres
REDIS_HOST=127.0.0.1
REDIS_PORT=6379
DB_PREFIX=edc_test_l
API_BASE_PORT=8000
FE_BASE_PORT=3000
PROFILE=clinical
EOF
  export HARNESS_ROOT="$TMPH"
  export LANES_ROOT="$TMPH/lanes"
}
teardown_temp_harness() { [ -n "${TMPH:-}" ] && rm -rf "$TMPH"; }

# Call the real state.sh under the temp HARNESS_ROOT.
st() { bash "$REPO/bin/state.sh" "$@"; }

assert_eq() {  # <expected> <actual> <name>
  if [ "$1" = "$2" ]; then PASS=$((PASS+1)); else
    FAIL=$((FAIL+1)); echo "  FAIL: $3"; echo "        expected: [$1]"; echo "        actual:   [$2]"; fi
}
assert_ne() {  # <a> <b> <name>  (assert NOT equal)
  if [ "$1" != "$2" ]; then PASS=$((PASS+1)); else
    FAIL=$((FAIL+1)); echo "  FAIL: $3 (both were [$1])"; fi
}
assert_file() {  # <path> <name>
  if [ -f "$1" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "  FAIL: $2 (missing file $1)"; fi
}
assert_contains() {  # <haystack> <needle> <name>
  case "$1" in *"$2"*) PASS=$((PASS+1));; *) FAIL=$((FAIL+1)); echo "  FAIL: $3 ([$1] lacks [$2])";; esac
}

finish() {  # print summary, exit nonzero on any failure
  echo "  $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ]
}
