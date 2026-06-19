#!/usr/bin/env bash
# Install backend (uv) + frontend (pnpm) deps for a clinical lane.
set -euo pipefail
echo "harness: backend deps (uv sync) ..."
( cd "$LANE_DIR/backend" && uv sync --extra dev )
echo "harness: frontend deps (pnpm install) ..."
( cd "$LANE_DIR/frontend" && pnpm install --frozen-lockfile )
