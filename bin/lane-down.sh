#!/usr/bin/env bash
# Stop a lane's api/worker/fe — recorded wrapper pids + ALL descendants
# (uvicorn/node/celery-prefork children) + a port-listener backstop.
# Idempotent and sleep-free.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
require_lane "${1:-}"
N="$1"; RUN="$(lane_run_dir "$N")"
API_PORT="$(lane_api_port "$N")"; FE_PORT="$(lane_fe_port "$N")"

# Recursively kill a pid and all its descendants (bottom-up).
kill_tree() {
  local p="$1" k
  for k in $(pgrep -P "$p" 2>/dev/null || true); do kill_tree "$k"; done
  kill -KILL "$p" 2>/dev/null || true
}

for svc in fe worker api; do
  pidfile="$RUN/$svc.pid"
  if [ -f "$pidfile" ]; then
    p="$(cat "$pidfile")"
    if [ -n "$p" ]; then
      echo "harness: stopping lane $N $svc (pid tree from $p)"
      kill_tree "$p"
    fi
    rm -f "$pidfile"
  fi
done

# Backstop: free the lane's API/FE ports by killing any remaining listeners.
for port in "$API_PORT" "$FE_PORT"; do
  lp="$(lsof -nP -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null || true)"
  if [ -n "$lp" ]; then
    for x in $lp; do kill -KILL "$x" 2>/dev/null || true; done
  fi
done

"$HARNESS_ROOT/bin/state.sh" "$N" set stage=down status=idle 2>/dev/null || true
echo "harness: lane $N down."
