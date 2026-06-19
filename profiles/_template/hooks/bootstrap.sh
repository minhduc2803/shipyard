#!/usr/bin/env bash
# bootstrap — install your app's dependencies in this lane clone.
# Env from run_hook: LANE LANE_DIR API_PORT FE_PORT DATABASE_URL REDIS_URL
#   UPLOAD_DIR DB_NAME API_BASE FE_URL RUN_DIR LOG_DIR PROFILE_DIR SOURCE_REPO
#   HARNESS_ROOT + every key from your profile.env (BACKEND_DIR, FRONTEND_DIR, …).
set -euo pipefail
# Clinical example:
#   ( cd "$LANE_DIR/$BACKEND_DIR"  && uv sync --extra dev )
#   ( cd "$LANE_DIR/$FRONTEND_DIR" && pnpm install --frozen-lockfile )
echo "harness: TODO — implement 'bootstrap' for your stack (see profiles/clinical/hooks/bootstrap.sh)" >&2
exit 1
