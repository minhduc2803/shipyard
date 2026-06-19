#!/usr/bin/env bash
# Cross-lane lock you can HOLD across non-shell work (MCP browser QC, etc.) —
# acquire/release style. Complements with-lock.sh (which wraps ONE command).
#   lane-lock.sh acquire <name> <N> [timeout_sec]   # waits (default 30 min)
#   lane-lock.sh release <name> <N>                  # only the holder lane can
#   lane-lock.sh status  <name>
# Atomicity via mkdir. Stale protection is TIME-based: a holder older than
# LOCK_MAX_HOLD (default 2700s = 45 min) is broken on the next acquire — a
# crashed session can't wedge the lock forever. ALWAYS release when done.
#
# ETIQUETTE (agents, read this): waiting on a held lock is NORMAL — the wait
# heartbeats your lane so the dashboard won't flag you stalled. NEVER try to
# free a lock by killing another lane's session/processes, deleting the lock
# dir, or shrinking LOCK_MAX_HOLD: the holder is doing real work (e.g. QC-ing
# the shared dev site) and stale holders expire on their own. If acquire times
# out, either re-run it or set your lane status=blocked and report — never force.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
ACTION="${1:?usage: lane-lock.sh acquire|release|status <name> [lane] [timeout]}"
NAME="${2:?lock name required}"
D="$HARNESS_ROOT/locks/$NAME.held"
OWNER="$D/owner"
now() { date +%s; }

max_hold() {  # floor at 5 min so a caller can't force-break a live lock via env
  local m="${LOCK_MAX_HOLD:-2700}"
  [[ "$m" =~ ^[0-9]+$ ]] && [ "$m" -ge 300 ] || m=300
  echo "$m"
}

holder_age() {
  local ts
  ts="$(awk '{print $2}' "$OWNER" 2>/dev/null)"
  [[ "$ts" =~ ^[0-9]+$ ]] || { echo ""; return; }
  echo $(( $(now) - ts ))
}

is_stale() {
  local age
  [ -f "$OWNER" ] || return 0
  age="$(holder_age)"
  [ -n "$age" ] || return 0
  [ "$age" -gt "$(max_hold)" ]
}

case "$ACTION" in
  acquire)
    require_lane "${3:-}"; N="$3"; TIMEOUT="${4:-${LOCK_TIMEOUT:-1800}}"
    mkdir -p "$HARNESS_ROOT/locks"
    start=$(now); waited=0; announced=""
    while :; do
      if mkdir "$D" 2>/dev/null; then
        echo "lane$N $(now)" > "$OWNER"
        echo "harness: '$NAME' lock acquired by lane $N (auto-expires after $(max_hold)s if not released)"
        exit 0
      fi
      if is_stale; then
        echo "harness: breaking stale '$NAME' lock (was: $(cat "$OWNER" 2>/dev/null || echo '?'), idle past $(max_hold)s)" >&2
        rm -rf "$D"
        continue
      fi
      if [ -z "$announced" ]; then
        echo "harness: '$NAME' lock held by $(cat "$OWNER" 2>/dev/null | awk '{print $1}' || echo '?') — lane $N waiting (NORMAL: do not kill the holder or rm the lock; stale holders auto-expire after $(max_hold)s)" >&2
        announced=1
      fi
      if [ $(( $(now) - start )) -ge "$TIMEOUT" ]; then
        die "'$NAME' lock not acquired within ${TIMEOUT}s — held by: $(cat "$OWNER" 2>/dev/null || echo '?'). Do NOT kill the holder's session/processes or delete the lock dir — it auto-expires after $(max_hold)s if the holder died. Re-run acquire (possibly with a longer timeout), or set your lane status=blocked with a note and report."
      fi
      sleep 3
      # heartbeat the WAITING lane (~every 60s) so the dashboard doesn't flag it stalled
      waited=$(( waited + 3 ))
      if [ $(( waited % 60 )) -lt 3 ]; then
        "$HARNESS_ROOT/bin/state.sh" "$N" set >/dev/null 2>&1 || true
      fi
    done
    ;;
  release)
    require_lane "${3:-}"; N="$3"
    if [ -f "$OWNER" ] && grep -q "^lane$N " "$OWNER"; then
      rm -rf "$D"
      echo "harness: '$NAME' lock released by lane $N"
    elif [ -d "$D" ]; then
      echo "harness: '$NAME' lock NOT held by lane $N (holder: $(cat "$OWNER" 2>/dev/null || echo '?')) — leaving it. Never force-release another lane's lock; if the holder died it auto-expires after $(max_hold)s." >&2
      exit 1
    else
      echo "harness: '$NAME' lock already free"
    fi
    ;;
  status)
    if [ -d "$D" ]; then
      echo "held: $(cat "$OWNER" 2>/dev/null || echo '?') (age: $(holder_age 2>/dev/null || echo '?')s; auto-expires past $(max_hold)s)"
    else
      echo "free"
    fi
    ;;
  *) die "unknown action '$ACTION' (acquire|release|status)";;
esac
