#!/usr/bin/env bash
# e2e — run your end-to-end suite against the RUNNING integrated stack.
# Run under the shared e2e lock so lanes don't collide:
#   "$HARNESS_ROOT/bin/with-lock.sh" e2e -- <your command>
set -euo pipefail
# Clinical example (Playwright, LOCAL_EXEC against the lane's host stack):
#   "$HARNESS_ROOT/bin/with-lock.sh" e2e -- bash -c "cd '$LANE_DIR/$FRONTEND_DIR' && \
#     E2E_API_BASE_URL='$API_BASE' E2E_FRONTEND_URL='$FE_URL' DATABASE_URL='$DATABASE_URL' \
#     pnpm exec playwright test --reporter=line"
echo "harness: TODO — implement 'e2e' for your stack (see profiles/clinical/hooks/e2e.sh)" >&2
exit 1
