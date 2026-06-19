#!/usr/bin/env bash
# boot — start your app's services for this lane, then RETURN (do not block).
# Use harness_spawn <name> <workdir> <cmd...> to background each service with
# detached stdio + pid/log tracking (lane-down.sh / lane-status.sh rely on it).
# Arg "$1" == "--no-build" means reuse the existing build.
set -euo pipefail
# IMPORTANT: if your frontend bakes the API URL at build time (e.g. NEXT_PUBLIC_*
# env vars in Next.js, VITE_* in Vite), you MUST:
#   1. Clear build caches before building (rm -rf .next/ or dist/) to prevent
#      stale API URLs from surviving across integration merges.
#   2. Set the URL to the lane's direct API address ($API_BASE, e.g.
#      http://localhost:800N/api/v1), NOT a relative path (/api/v1) — the
#      frontend server has no proxy; relative paths hit the frontend port
#      which returns 404 for API routes.
# Clinical example:
#   harness_spawn api    "$LANE_DIR/$BACKEND_DIR"  uv run uvicorn app.main:app --host 0.0.0.0 --port "$API_PORT"
#   harness_spawn worker "$LANE_DIR/$BACKEND_DIR"  uv run celery -A app.workers.celery_app:celery worker -Q "$WORKER_QUEUES"
#   export NEXT_PUBLIC_API_BASE_URL="$API_BASE" PORT="$FE_PORT" HOSTNAME=0.0.0.0
#   # Clean .next/ before build to prevent stale API URL or route manifests:
#   rm -rf "$LANE_DIR/$FRONTEND_DIR/.next" && pnpm build
#   harness_spawn fe     "$LANE_DIR/$FRONTEND_DIR" node .next/standalone/server.js
echo "harness: TODO — implement 'boot' for your stack (see profiles/clinical/hooks/boot.sh)" >&2
exit 1
