#!/usr/bin/env bash
# Harness watch dashboard (Node.js + React).
#   dashboard.sh [port]         # foreground (Ctrl-C to stop)
#   dashboard.sh start [port]   # DETACHED daemon (nohup) — survives terminal/session close
#   dashboard.sh stop           # stop the detached daemon
#   dashboard.sh status         # running?
#   dashboard.sh restart [port]
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
export HARNESS_ROOT LANES_ROOT FE_BASE_PORT API_BASE_PORT PROFILE
PIDFILE="$HARNESS_ROOT/run/dashboard.pid"
LOG="$HARNESS_ROOT/logs/dashboard.log"
DASHBOARD_DIR="$HARNESS_ROOT/dashboard"
mkdir -p "$HARNESS_ROOT/run" "$HARNESS_ROOT/logs"

command -v node >/dev/null 2>&1 || { echo "harness: 'node' not found — install Node.js first" >&2; exit 1; }

_running() { [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; }
_free_port() {
  local p="$1" lp
  lp="$(lsof -nP -iTCP:"$p" -sTCP:LISTEN -t 2>/dev/null || true)"
  if [ -n "$lp" ]; then
    for x in $lp; do kill -TERM "$x" 2>/dev/null || true; done
    sleep 0.3
    for x in $lp; do kill -0 "$x" 2>/dev/null && kill -KILL "$x" 2>/dev/null; done || true
  fi
}
_ensure_deps() {
  [ -d "$DASHBOARD_DIR/node_modules" ] && return 0
  echo "harness: installing dashboard dependencies …"
  (cd "$DASHBOARD_DIR" && npm ci --production) || { echo "harness: npm ci failed" >&2; exit 1; }
}

case "${1:-fg}" in
  start)
    PORT="${2:-${DASHBOARD_PORT:-8090}}"
    if _running; then echo "harness: dashboard already running (pid $(cat "$PIDFILE")) -> http://127.0.0.1:$PORT"; exit 0; fi
    _ensure_deps; _free_port "$PORT"
    nohup node "$DASHBOARD_DIR/server/index.js" "$PORT" >"$LOG" 2>&1 &
    echo $! >"$PIDFILE"; disown 2>/dev/null || true
    echo "harness: dashboard started (pid $(cat "$PIDFILE")) -> http://127.0.0.1:$PORT  (log: $LOG)"
    ;;
  stop)
    if _running; then kill "$(cat "$PIDFILE")" 2>/dev/null || true; fi
    rm -f "$PIDFILE"; echo "harness: dashboard stopped."
    ;;
  status)
    if _running; then echo "harness: dashboard running (pid $(cat "$PIDFILE"))."; else echo "harness: dashboard NOT running."; fi
    ;;
  restart)
    "$0" stop || true; exec "$0" start "${2:-}"
    ;;
  fg)
    PORT="${2:-${DASHBOARD_PORT:-8090}}"; _ensure_deps; _free_port "$PORT"
    exec node "$DASHBOARD_DIR/server/index.js" "$PORT"
    ;;
  *)  # bare numeric port -> foreground on that port (back-compat with `dashboard.sh 8090`)
    _ensure_deps; _free_port "$1"; exec node "$DASHBOARD_DIR/server/index.js" "$1"
    ;;
esac
