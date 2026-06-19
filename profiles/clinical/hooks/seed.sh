#!/usr/bin/env bash
# Seed the initial user/org. DATABASE_URL + SEED_USER_* exported by run_hook.
set -euo pipefail
( cd "$LANE_DIR/backend" && uv run bash scripts/init_user.sh )
