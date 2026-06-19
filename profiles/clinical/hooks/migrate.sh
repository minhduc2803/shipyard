#!/usr/bin/env bash
# Apply DB migrations to the lane DB. DATABASE_URL is exported by run_hook.
set -euo pipefail
( cd "$LANE_DIR/backend" && uv run python -m app.db.migrate upgrade )
