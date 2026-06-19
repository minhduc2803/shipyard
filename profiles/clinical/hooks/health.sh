#!/usr/bin/env bash
# Readiness probe for a booted clinical lane. exit 0 only if API and FE are up.
# curl handles retry/backoff internally (no shell sleep); --max-time bounds each
# attempt so a wedged-but-listening server can't hang the probe forever.
set -euo pipefail
ok=0
echo "harness: waiting for API health ($API_BASE/health) ..."
curl -fsS --retry 60 --retry-delay 2 --retry-all-errors --retry-connrefused --max-time 5 \
  "$API_BASE/health" >/dev/null 2>&1 && echo "harness: API ok" || { echo "harness: API NOT healthy" >&2; ok=1; }
echo "harness: waiting for FE ($FE_URL/login) ..."
curl -fsS --retry 40 --retry-delay 2 --retry-all-errors --retry-connrefused --max-time 5 \
  "$FE_URL/login" >/dev/null 2>&1 && echo "harness: FE ok" || { echo "harness: FE NOT healthy" >&2; ok=1; }
exit "$ok"
