#!/usr/bin/env bash
# migrate — apply DB migrations to this lane's DB. DATABASE_URL is exported.
set -euo pipefail
# Clinical example:
#   ( cd "$LANE_DIR/$BACKEND_DIR" && uv run python -m app.db.migrate upgrade )
echo "harness: TODO — implement 'migrate' for your stack (see profiles/clinical/hooks/migrate.sh)" >&2
exit 1
