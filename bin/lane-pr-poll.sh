#!/usr/bin/env bash
# PR-review poll helper for the /review-prs skill. Lists open PRs on the lane's
# repo and classifies each against a per-lane cursor so the loop only acts on PRs
# that need our input. Also maintains the cursor + an append-only review history
# the dashboard renders. Read-only except `mark`/`log` (which touch lane state).
#
#   lane-pr-poll.sh <N> list                       # classify open PRs (heartbeats)
#   lane-pr-poll.sh <N> mark <pr>                   # snapshot PR's current state (after handling it)
#   lane-pr-poll.sh <N> log <pr> <action> <detail> # append a review-history event
#
# Classification (vs cursor harness/state/laneN-prcursor.json):
#   NEW       — never handled
#   UPDATED   — new commits since we last reviewed (head sha changed)
#   TOUCHED   — updatedAt moved but sha unchanged (likely new comments → check)
#   UPTODATE  — nothing new (skip)
# Env: LANE_PR_INCLUDE_OWN=1 (review your own PRs too; default skip),
#      LANE_PR_INCLUDE_DRAFTS=1 (default skip drafts).
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
require_lane "${1:-}"
N="$1"; ACTION="${2:-list}"; shift 2 || true
DIR="$(lane_dir "$N")"
[ -d "$DIR/.git" ] || die "lane $N not bootstrapped"
CURSOR="$HARNESS_ROOT/state/lane$N-prcursor.json"
REVIEWS="$HARNESS_ROOT/state/lane$N-reviews.json"
GH_TOKEN="$(gh auth token 2>/dev/null || true)"; export GH_TOKEN  # keyring 401 workaround
now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

case "$ACTION" in
  list)
    "$HARNESS_ROOT/bin/state.sh" "$N" set >/dev/null 2>&1 || true   # heartbeat
    me="$(gh api user --jq .login 2>/dev/null || echo '')"
    prs="$(cd "$DIR" && gh pr list --state open --limit 100 \
            --json number,title,url,author,headRefOid,updatedAt,isDraft,reviewDecision,mergeable,mergeStateStatus,statusCheckRollup 2>/dev/null || echo '[]')"
    NA_OUT="$(mktemp)"
    CURSOR="$CURSOR" ME="$me" INCLUDE_OWN="${LANE_PR_INCLUDE_OWN:-0}" INCLUDE_DRAFTS="${LANE_PR_INCLUDE_DRAFTS:-0}" NA_OUT="$NA_OUT" \
    python3 - "$prs" <<'PY'
import json, os, sys
prs = json.loads(sys.argv[1] or "[]")
cur = {}
cpath = os.environ["CURSOR"]
if os.path.exists(cpath):
    try: cur = json.load(open(cpath))
    except Exception: cur = {}
me = os.environ.get("ME", ""); inc_own = os.environ.get("INCLUDE_OWN") == "1"
inc_drafts = os.environ.get("INCLUDE_DRAFTS") == "1"
order = {"NEW": 0, "UPDATED": 1, "TOUCHED": 2, "UPTODATE": 3}

def ci_state(rollup):
    # green = all checks passed, pending = some still running, failing = any failed, none = no checks
    if not rollup: return "none"
    fail = pending = False
    for c in rollup:
        if c.get("__typename") == "StatusContext" or ("state" in c and "conclusion" not in c):
            st = (c.get("state") or "").upper()
            if st in ("FAILURE", "ERROR"): fail = True
            elif st in ("PENDING", "EXPECTED"): pending = True
        else:  # CheckRun
            st = (c.get("status") or "").upper(); concl = (c.get("conclusion") or "").upper()
            if st and st != "COMPLETED": pending = True
            elif concl in ("FAILURE", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE", "STALE"): fail = True
    return "failing" if fail else ("pending" if pending else "green")

rows = []; ready = []; awaiting = []
for p in prs:
    if p.get("isDraft") and not inc_drafts:
        continue
    author = (p.get("author") or {}).get("login", "")
    if author == me and not inc_own:
        continue
    key = str(p["number"]); c = cur.get(key)
    sha = p.get("headRefOid", ""); upd = p.get("updatedAt", "")
    if not c:
        cls = "NEW"
    elif c.get("sha") != sha:
        cls = "UPDATED"
    elif c.get("updatedAt") != upd:
        cls = "TOUCHED"
    else:
        cls = "UPTODATE"
    rd = p.get("reviewDecision") or "-"
    mss = (p.get("mergeStateStatus") or "").upper()
    mrg = (p.get("mergeable") or "").upper()
    ci = ci_state(p.get("statusCheckRollup") or [])
    num = p["number"]
    # ready    = GitHub says it's mergeable now (CLEAN), or green + approved + no conflicts
    # awaiting = our review is done + CI green + no conflicts + not changes-requested,
    #            but it still needs a human approval/merge (ball is in YOUR court)
    is_ready = (mss == "CLEAN") or (mrg == "MERGEABLE" and rd == "APPROVED" and ci in ("green", "none"))
    is_await = (not is_ready) and ci in ("green", "none") and mrg != "CONFLICTING" \
               and rd != "CHANGES_REQUESTED" and cls == "UPTODATE"
    if is_ready: ready.append(num)
    elif is_await: awaiting.append(num)
    act = "ready" if is_ready else ("awaiting" if is_await else "-")
    rows.append((order[cls], cls, num, author, sha, rd, ci, act, p.get("title", "")))
rows.sort()
actionable = sum(1 for r in rows if r[1] != "UPTODATE")
print(f"PR_POLL: {len(rows)} open · {actionable} need review · {len(ready)} ready to merge · {len(awaiting)} awaiting your decision")
print("# columns: CLASS  #PR  HEAD_SHA(full — pass to `mark`)  AUTHOR  REVIEW  CI  MERGE_ACTION  TITLE")
for _, cls, num, author, sha, rd, ci, act, title in rows:
    print(f"{cls}\t#{num}\t{sha}\t{author}\t{rd}\t{ci}\t{act}\t{title}")

parts = []
if ready:    parts.append("✅ ready to merge: " + ", ".join("#%d" % n for n in ready))
if awaiting: parts.append("🙋 awaiting your review/merge: " + ", ".join("#%d" % n for n in awaiting))
open(os.environ["NA_OUT"], "w").write(" · ".join(parts))
PY
    NA="$(cat "$NA_OUT" 2>/dev/null || true)"; rm -f "$NA_OUT"
    "$HARNESS_ROOT/bin/state.sh" "$N" set needs_action="$NA" >/dev/null 2>&1 || true
    ;;
  mark)
    # Snapshot the PR's CURRENT state from GitHub so the next `list` compares
    # against real values (call this AFTER you've reviewed/responded to the PR).
    PR="${1:?usage: mark <pr>}"
    snap="$(cd "$DIR" && gh pr view "$PR" --json headRefOid,updatedAt,comments 2>/dev/null || echo '{}')"
    CURSOR="$CURSOR" python3 - "$PR" "$(now_iso)" "$snap" <<'PY'
import json, os, sys
pr, ts, snap = sys.argv[1], sys.argv[2], json.loads(sys.argv[3] or "{}")
cpath = os.environ["CURSOR"]
cur = {}
if os.path.exists(cpath):
    try: cur = json.load(open(cpath))
    except Exception: cur = {}
cur[str(pr)] = {
    "sha": snap.get("headRefOid", ""),
    "updatedAt": snap.get("updatedAt", ""),
    "comment_count": len(snap.get("comments") or []),
    "handled_ts": ts,
}
json.dump(cur, open(cpath, "w"), indent=2)
print(f"marked #{pr} @ {cur[str(pr)]['sha'][:8] or '?'}")
PY
    ;;
  log)
    PR="${1:?pr number}"; EVT="${2:?action}"; DETAIL="${3:-}"
    REVIEWS="$REVIEWS" python3 - "$PR" "$EVT" "$DETAIL" "$(now_iso)" <<'PY'
import json, os, sys
pr, evt, detail, ts = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
rpath = os.environ["REVIEWS"]
hist = []
if os.path.exists(rpath):
    try: hist = json.load(open(rpath))
    except Exception: hist = []
hist.append({"ts": ts, "pr": int(pr), "action": evt, "detail": detail[:300]})
hist = hist[-100:]   # cap
json.dump(hist, open(rpath, "w"), indent=2)
print(f"logged {evt} #{pr}")
PY
    ;;
  *) die "unknown action '$ACTION' (list|mark|log)";;
esac
