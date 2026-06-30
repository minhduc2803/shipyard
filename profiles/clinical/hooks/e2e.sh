#!/usr/bin/env bash
# Playwright e2e for a clinical lane against its RUNNING integrated stack.
# The lane runs API/FE as HOST processes (no per-lane api container), so we drive
# the fixture in LOCAL_EXEC mode: seed on the host + talk to the lane DB directly.
# JWT_SECRET must match the running lane API (lane-up wrote it to backend/.env).
set -euo pipefail
LANE_JWT="$(grep -E '^JWT_SECRET=' "$LANE_DIR/backend/.env" 2>/dev/null | head -1 | cut -d= -f2-)"
[ -n "$LANE_JWT" ] || { echo "e2e: JWT_SECRET not found in $LANE_DIR/backend/.env (stack booted?)" >&2; exit 1; }
# Hard wall-clock on the test run so a hung suite fails loudly instead of
# stranding the lane at stage=e2e forever (E2E_TIMEOUT secs, default 20m;
# SIGKILL 30s after SIGTERM). Bounds execution only — the lock wait is bounded
# separately by with-lock.sh.
rc=0
"$HARNESS_ROOT/bin/with-lock.sh" e2e -- bash -c "cd '$LANE_DIR/frontend' && \
  E2E_NO_WEBSERVER=1 \
  E2E_LOCAL_EXEC=1 \
  E2E_API_BASE_URL='$API_BASE' \
  E2E_FRONTEND_URL='$FE_URL' \
  E2E_DB_HOST='$PG_HOST' E2E_DB_PORT='$PG_PORT' E2E_DB_USER='$PG_USER' \
  E2E_DB_PASSWORD='$PG_PASS' E2E_DB_NAME='$DB_NAME' \
  E2E_JWT_SECRET='$LANE_JWT' \
  DATABASE_URL='$DATABASE_URL' \
  timeout -k 30 ${E2E_TIMEOUT:-1200} pnpm exec playwright test --reporter=line" || rc=$?
if [ "$rc" -eq 124 ]; then
  echo "e2e: TIMED OUT after ${E2E_TIMEOUT:-1200}s — treating as FAIL (raise E2E_TIMEOUT if the suite legitimately needs longer)." >&2
fi
exit "$rc"
