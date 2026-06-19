#!/usr/bin/env bash
# Seam unit-test fixture: prove run_hook exports the contract + functions.
set -euo pipefail
echo "HOOK_OK lane=$LANE dir=$LANE_DIR api=$API_PORT fe=$FE_PORT db=$DATABASE_URL profile_dir=$PROFILE_DIR"
type harness_spawn >/dev/null 2>&1 && echo "SPAWN_FN_OK"
type die >/dev/null 2>&1 && echo "DIE_FN_OK"
