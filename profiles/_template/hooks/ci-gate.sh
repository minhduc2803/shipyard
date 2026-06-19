#!/usr/bin/env bash
# ci-gate — pre-push checks (lint / test / contract). Exit non-zero on first failure.
# The engine provides TEST_DATABASE_URL (an isolated, freshly-created DB) for tests.
set -euo pipefail
# Clinical example:
#   ( cd "$LANE_DIR" && make openapi-check-host )
#   ( cd "$LANE_DIR/$BACKEND_DIR" && DATABASE_URL="$TEST_DATABASE_URL" REDIS_URL="$REDIS_URL" uv run pytest app/tests -q )
#   "$HARNESS_ROOT/bin/with-lock.sh" build -- bash -c "cd '$LANE_DIR/$FRONTEND_DIR' && pnpm build:check"
echo "harness: TODO — implement 'ci-gate' for your stack (see profiles/clinical/hooks/ci-gate.sh)" >&2
exit 1
