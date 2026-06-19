#!/usr/bin/env bash
# Read/update a lane's JSON state file. Uses python3 (no jq dependency).
# State lives in state/laneN/<slug>.json (per-feature); .active points to current.
#   state.sh <N> init                        # create with defaults (migrates old flat file)
#   state.sh <N> set key=value [key=value]   # merge keys; bumps last_heartbeat
#   state.sh <N> get [key]                   # print whole JSON, or one key
#   state.sh <N> activate <slug>             # set .active + rename _pending if needed
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
require_lane "${1:-}"
N="$1"; ACTION="${2:-get}"; shift 2 || true
FILE="$(lane_state_file "$N")"
mkdir -p "$(dirname "$FILE")"

case "$ACTION" in
  init)
    # Migrate old flat file to per-feature directory on first init
    STATE_DIR="$HARNESS_ROOT/state/lane$N"
    if [ -f "$STATE_DIR.json" ] && [ ! -d "$STATE_DIR" ]; then
      mkdir -p "$STATE_DIR"
      old_branch="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("branch",""))' "$STATE_DIR.json" 2>/dev/null || echo "")"
      old_slug="${old_branch#feat/}"
      old_slug="${old_slug//\//-}"
      if [ -n "$old_slug" ]; then
        mv "$STATE_DIR.json" "$STATE_DIR/$old_slug.json"
      else
        mv "$STATE_DIR.json" "$STATE_DIR/_pending.json"
      fi
    fi
    # Clear .active pointer — init means fresh lane state
    mkdir -p "$STATE_DIR"
    : > "$STATE_DIR/.active"
    # Re-resolve FILE after potential migration
    FILE="$(lane_state_file "$N")"
    mkdir -p "$(dirname "$FILE")"
    MANUAL_URL="$(lane_fe_url "$N")" python3 - "$FILE" "$N" <<'PY'
import json, os, sys, datetime, tempfile
def atomic_write(path, doc):
    # Concurrent readers (the dashboard) must never see a partial file.
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path) or ".", prefix=os.path.basename(path) + ".", suffix=".tmp")
    with os.fdopen(fd, "w") as fh:
        fh.write(json.dumps(doc, indent=2) + "\n")
    os.replace(tmp, path)
path, n = sys.argv[1], int(sys.argv[2])
doc = {
  "lane": n, "feature_title": "", "branch": "", "pr_url": "", "ticket_url": "",
  "stage": "idle", "status": "idle", "gate_decision": "pending", "qc_dev": "",
  "mode": "ship", "ci_status": "", "manual_test_url": os.environ["MANUAL_URL"],
  "needs_action": "",
  "last_heartbeat": datetime.datetime.now(datetime.timezone.utc).isoformat(),
  "stage_since": datetime.datetime.now(datetime.timezone.utc).isoformat(),
  "notes": "",
}
atomic_write(path, doc)
PY
    ;;
  activate)
    slug="${1:-}"
    [ -n "$slug" ] || die "usage: state.sh <N> activate <slug>"
    # Canonicalize to a SINGLE-SEGMENT slug: drop any feat/ prefix, turn path
    # separators + spaces into '-', keep only safe chars. This keeps the state
    # file (state/laneN/<slug>.json), the .active pointer, and the proof dir
    # (proof/<slug>/) flat and IDENTICAL so the dashboard can join them by slug.
    # (state.sh init's legacy migration sanitizes the same way.)
    slug="${slug#feat/}"; slug="$(printf '%s' "$slug" | tr '/ ' '--' | tr -cd 'A-Za-z0-9._-')"
    [ -n "$slug" ] || die "slug became empty after sanitizing"
    STATE_DIR="$HARNESS_ROOT/state/lane$N"
    mkdir -p "$STATE_DIR"
    # If _pending.json exists and target doesn't, rename it
    if [ -f "$STATE_DIR/_pending.json" ] && [ ! -f "$STATE_DIR/$slug.json" ]; then
      mv "$STATE_DIR/_pending.json" "$STATE_DIR/$slug.json"
    fi
    printf '%s' "$slug" > "$STATE_DIR/.active"
    printf '%s\n' "$slug"   # echo the canonical slug so callers can capture it
    ;;
  set)
    [ -f "$FILE" ] || { "$0" "$N" init; }
    python3 - "$FILE" "$@" <<'PY'
import json, os, sys, datetime, tempfile, fcntl
path = sys.argv[1]
def atomic_write(path, doc):
    # Concurrent readers (the dashboard) must never see a partial file.
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path) or ".", prefix=os.path.basename(path) + ".", suffix=".tmp")
    with os.fdopen(fd, "w") as fh:
        fh.write(json.dumps(doc, indent=2) + "\n")
    os.replace(tmp, path)
# Serialize the whole read-modify-write across processes: the main session, the
# background dev-qc / ticketer agents, and the heartbeat tickers all write this
# file. os.replace already prevents torn *reads*; this exclusive lock prevents
# lost *updates* — one writer's set silently reverting another's (e.g. a
# heartbeat clobbering dev-qc's qc_dev=passed).
with open(path + ".lock", "w") as _lk:
    fcntl.flock(_lk, fcntl.LOCK_EX)
    try:
        doc = json.load(open(path))
    except Exception:
        doc = {}   # tolerate a momentarily-unreadable file; the set still lands
    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
    prev_stage = doc.get("stage")
    keys = [kv.partition("=")[0] for kv in sys.argv[2:]]
    for kv in sys.argv[2:]:
        k, _, v = kv.partition("=")
        doc[k] = v
    # stage_since = when the lane ENTERED its current stage, so the dashboard can
    # show time-on-phase. Moves only when the stage value actually changes; a bare
    # heartbeat set (no args) or a same-stage set leaves it untouched. Backfills
    # for lanes created before this field existed.
    if "stage" in keys and doc.get("stage") != prev_stage:
        doc["stage_since"] = now
    if not doc.get("stage_since"):
        doc["stage_since"] = now
    doc["last_heartbeat"] = now
    atomic_write(path, doc)
PY
    ;;
  get)
    [ -f "$FILE" ] || die "no state for lane $N (run: state.sh $N init)"
    if [ "${1:-}" ]; then
      python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2],""))' "$FILE" "$1"
    else
      cat "$FILE"
    fi
    ;;
  *) die "unknown action '$ACTION' (init|set|get|activate)";;
esac
