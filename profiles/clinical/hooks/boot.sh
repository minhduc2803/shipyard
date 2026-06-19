#!/usr/bin/env bash
# Boot the clinical stack for a lane: uvicorn API + Celery worker + Next
# standalone FE. Uses harness_spawn (detached) so callers never hang on a pipe.
# Arg: --no-build reuses the existing FE build. Env contract from run_hook.
set -euo pipefail
BUILD=1; [ "${1:-}" == "--no-build" ] && BUILD=0
BACKEND="$LANE_DIR/backend"; FRONTEND="$LANE_DIR/frontend"
export AWS_EC2_METADATA_DISABLED=true

echo "harness: starting API on :$API_PORT ..."
harness_spawn api "$BACKEND" uv run uvicorn app.main:app --host 0.0.0.0 --port "$API_PORT"

echo "harness: starting worker ..."
# macOS: Celery's prefork pool forks worker children; a dependency that touches
# Obj-C/Cocoa (e.g. via AWS libs) aborts the forked child with a fork-safety
# SIGABRT ("+[NSCharacterSet initialize] may have been in progress ... Crashing
# instead"), crash-looping the worker so NO ingest/extraction ever runs. Disable
# the fork-safety check so children survive. On Linux CI this var is a harmless
# no-op.
export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES
harness_spawn worker "$BACKEND" uv run celery -A app.workers.celery_app:celery worker \
  --loglevel=info --concurrency=2 -Q "$WORKER_QUEUES"

export NEXT_PUBLIC_API_BASE_URL="$API_BASE"
export NEXT_TELEMETRY_DISABLED=1
export NODE_OPTIONS="${NODE_OPTIONS:---max-old-space-size=2048}"
if [ "$BUILD" == 1 ]; then
  echo "harness: building FE (under build lock) ..."
  "$HARNESS_ROOT/bin/with-lock.sh" build -- bash -c "cd '$FRONTEND' && \
    rm -rf .next && \
    NEXT_PUBLIC_API_BASE_URL='$NEXT_PUBLIC_API_BASE_URL' pnpm build && \
    rm -rf .next/standalone/.next/static && mkdir -p .next/standalone/.next && \
    cp -R .next/static .next/standalone/.next/static && \
    { [ -d public ] && { rm -rf .next/standalone/public; cp -R public .next/standalone/public; } || true; }"
fi
echo "harness: starting FE on :$FE_PORT ..."
export PORT="$FE_PORT" HOSTNAME=0.0.0.0
harness_spawn fe "$FRONTEND" node .next/standalone/server.js
