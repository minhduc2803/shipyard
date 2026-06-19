#!/usr/bin/env bash
# health — exit 0 only when this lane's app is fully ready. API_BASE / FE_URL exported.
# Prefer curl --retry (handles backoff itself; no shell sleep).
set -euo pipefail
# Clinical example:
#   curl -fsS --retry 60 --retry-delay 2 --retry-connrefused --max-time 5 "$API_BASE/health" >/dev/null
#   curl -fsS --retry 40 --retry-delay 2 --retry-connrefused --max-time 5 "$FE_URL/login"     >/dev/null
echo "harness: TODO — implement 'health' for your stack (see profiles/clinical/hooks/health.sh)" >&2
exit 1
