#!/usr/bin/env bash
# Poll a lane's PR for review feedback + base-branch conflicts. Prints:
#   PR_STATE: OPEN|MERGED|CLOSED
#   PR_MERGEABLE: MERGEABLE|CONFLICTING|UNKNOWN (mergeStateStatus)
#   --- [kind] author timestamp [file:line]   (one block per NEW item)
#   <body>
#   NEW_COMMENTS: <count>
# "New" = created after this lane's cursor (state/laneN.pr-cursor), which
# advances each run. Covers issue comments, inline review comments, and
# review verdicts (APPROVED / CHANGES_REQUESTED / ...). Bumps the heartbeat.
# Note: GitHub computes mergeability lazily — UNKNOWN on the first poll after a
# push is normal and resolves by the next poll.
#   lane-pr-comments.sh <N> [pr_url]      # pr_url defaults to the lane state's
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
require_lane "${1:-}"
N="$1"
PR_URL="${2:-$("$HARNESS_ROOT/bin/state.sh" "$N" get pr_url 2>/dev/null || true)}"
[ -n "$PR_URL" ] || die "lane $N has no pr_url in state and none was passed"
# Per-feature cursor: lives beside the lane's per-feature state, keyed by the
# ACTIVE feature slug, so a new feature on this lane starts with a fresh cursor
# (no stale timestamp from the previous feature suppressing its early comments).
STATE_DIR="$HARNESS_ROOT/state/lane$N"; mkdir -p "$STATE_DIR"
ACTIVE_SLUG=""
[ -f "$STATE_DIR/.active" ] && ACTIVE_SLUG="$(tr -d '[:space:]' < "$STATE_DIR/.active" 2>/dev/null || true)"
if [ -n "$ACTIVE_SLUG" ]; then
  CURSOR_FILE="$STATE_DIR/$ACTIVE_SLUG.pr-cursor"
else
  CURSOR_FILE="$HARNESS_ROOT/state/lane$N.pr-cursor"   # back-compat (pre per-feature state)
fi

read -r OWNER REPO NUM <<<"$(python3 - "$PR_URL" <<'PY'
import re, sys
m = re.search(r"github\.com[/:]([^/]+)/([^/]+?)(?:\.git)?/pull/(\d+)", sys.argv[1])
print(*m.groups()) if m else sys.exit(1)
PY
)" || die "cannot parse PR url: $PR_URL"

PRINFO="$(gh pr view "$PR_URL" --json state,mergeable,mergeStateStatus \
  -q '.state + " " + (.mergeable // "UNKNOWN") + " " + (.mergeStateStatus // "UNKNOWN")' \
  2>/dev/null || echo "UNKNOWN UNKNOWN UNKNOWN")"
read -r STATE MERGEABLE MSTATUS <<<"$PRINFO"
echo "PR_STATE: $STATE"
echo "PR_MERGEABLE: $MERGEABLE ($MSTATUS)"

OWNER="$OWNER" REPO="$REPO" NUM="$NUM" CURSOR_FILE="$CURSOR_FILE" python3 <<'PY'
import json, os, subprocess

o, r, num = os.environ["OWNER"], os.environ["REPO"], os.environ["NUM"]
cursor_file = os.environ["CURSOR_FILE"]
cur = "1970-01-01T00:00:00Z"
if os.path.exists(cursor_file):
    cur = open(cursor_file).read().strip() or cur

def gh(path):
    out = subprocess.run(["gh", "api", path], capture_output=True, text=True)
    if out.returncode != 0:
        return []
    try:
        data = json.loads(out.stdout)
        return data if isinstance(data, list) else []
    except Exception:
        return []

items = []
for c in gh(f"repos/{o}/{r}/issues/{num}/comments?per_page=100"):
    items.append((c["created_at"], "comment", c["user"]["login"], "", c.get("body") or ""))
for c in gh(f"repos/{o}/{r}/pulls/{num}/comments?per_page=100"):
    loc = f'{c.get("path","")}:{c.get("line") or c.get("original_line") or ""}'
    items.append((c["created_at"], "review-comment", c["user"]["login"], loc, c.get("body") or ""))
for c in gh(f"repos/{o}/{r}/pulls/{num}/reviews?per_page=100"):
    ts = c.get("submitted_at")
    if not ts:
        continue
    body, st = (c.get("body") or ""), c.get("state", "")
    if not body and st == "COMMENTED":
        continue  # empty container review for inline comments (already listed)
    items.append((ts, f"review:{st}", c["user"]["login"], "", body))

new = sorted(i for i in items if i[0] > cur)
for ts, kind, who, loc, body in new:
    head = f"--- [{kind}] {who} {ts}" + (f" {loc}" if loc else "")
    print(head)
    print(body.strip())
    print()
print(f"NEW_COMMENTS: {len(new)}")

if items:
    mx = max(i[0] for i in items)
    if mx > cur:
        open(cursor_file, "w").write(mx)
PY

"$HARNESS_ROOT/bin/state.sh" "$N" set >/dev/null 2>&1 || true   # heartbeat
