#!/usr/bin/env bash
# Pre-push CI gates for a clinical lane: openapi-check + backend pytest +
# frontend build:check. The engine provides an isolated TEST_DATABASE_URL so
# pytest never touches the lane's working DB.
set -euo pipefail
echo "harness: [gate 1/3] openapi-check (contract drift) ..."
( cd "$LANE_DIR" && make openapi-check-host )
echo "harness: [gate 2/3] backend pytest ..."
( cd "$LANE_DIR/backend" && DATABASE_URL="$TEST_DATABASE_URL" REDIS_URL="$REDIS_URL" \
    uv run pytest app/tests --ignore=app/tests/integration -q )
echo "harness: [gate 3/3] frontend build:check (eslint + build) ..."
"$HARNESS_ROOT/bin/with-lock.sh" build -- bash -c "cd '$LANE_DIR/frontend' && pnpm build:check"
