#!/usr/bin/env bash
# GATED — call ONLY after the senior agent returns GO (spec stage 8).
# Under integration.lock (one lane integrates at a time):
#   - if origin/development is UNCHANGED since integrate: push the already-
#     validated local merge as-is (keeps the exact tested commit);
#   - if origin/development MOVED: discard the local merge entirely, reset
#     development to the latest origin, and RE-MERGE the feature branch fresh
#     (history stays clean: latest dev + one merge commit), then push.
# Pushing `development` auto-deploys dev.
#   lane-push-dev.sh <N> [feature_branch]
#     feature_branch defaults to the lane state's branch field
#     ("development+<feature>") or the last merge commit's subject.
# Exit 3 = the fresh re-merge CONFLICTS with the newer development. Local
# development is left reset to origin/development (old merge discarded) —
# re-run stage 4 (lane-integrate resolves conflicts inline), re-QC, re-gate.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
require_lane "${1:-}"
N="$1"; DIR="$(lane_dir "$N")"
[ -d "$DIR/.git" ] || die "lane $N not bootstrapped"
[ "$(git -C "$DIR" rev-parse --abbrev-ref HEAD)" = "$INTEGRATION_BRANCH" ] \
  || die "lane $N not on development (run lane-integrate first)"

FEATURE="${2:-}"
if [ -z "$FEATURE" ]; then
  SB="$("$HARNESS_ROOT/bin/state.sh" "$N" get branch 2>/dev/null || true)"
  case "$SB" in "$INTEGRATION_BRANCH"+*) FEATURE="${SB#"$INTEGRATION_BRANCH"+}";; esac
fi
if [ -z "$FEATURE" ]; then
  FEATURE="$(git -C "$DIR" log -1 --format=%s "$INTEGRATION_BRANCH" | sed -n "s/^Merge branch '\([^']*\)'.*/\1/p")"
fi
[ -n "$FEATURE" ] || die "cannot determine the feature branch — pass it: lane-push-dev.sh $N <feature_branch>"
git -C "$DIR" rev-parse --verify "$FEATURE" >/dev/null 2>&1 \
  || die "feature branch '$FEATURE' not found in lane $N"

"$HARNESS_ROOT/bin/state.sh" "$N" set stage=pushing-development status=running

set +e
"$HARNESS_ROOT/bin/with-lock.sh" integration -- bash -c "
  set -euo pipefail
  git -C '$DIR' fetch origin --prune
  git -C '$DIR' checkout $INTEGRATION_BRANCH
  if git -C '$DIR' merge-base --is-ancestor origin/$INTEGRATION_BRANCH $INTEGRATION_BRANCH; then
    echo 'harness: origin/$INTEGRATION_BRANCH unchanged — pushing the validated merge as-is'
  else
    echo 'harness: origin/$INTEGRATION_BRANCH moved — discarding local merge, resetting, re-merging $FEATURE fresh'
    git -C '$DIR' reset --hard origin/$INTEGRATION_BRANCH
    if ! git -C '$DIR' merge --no-edit '$FEATURE'; then
      git -C '$DIR' merge --abort 2>/dev/null || true
      exit 3
    fi
  fi
  git -C '$DIR' push origin $INTEGRATION_BRANCH
"
rc=$?
set -e

if [ "$rc" = 3 ]; then
  "$HARNESS_ROOT/bin/state.sh" "$N" set stage=push-conflict status=running \
    notes="fresh re-merge of $FEATURE conflicts with newer origin/development (local dev reset to origin) — re-run stage 4, re-QC, re-gate"
  die "lane $N: re-merge of '$FEATURE' onto the latest development conflicts — re-run lane-integrate (stage 4, resolves inline), re-QC, re-gate, then push again"
elif [ "$rc" != 0 ]; then
  "$HARNESS_ROOT/bin/state.sh" "$N" set stage=push-failed status=failed notes="git push failed (rc=$rc)"
  die "lane $N: development push failed (rc=$rc)"
fi

"$HARNESS_ROOT/bin/state.sh" "$N" set stage=pushed-development status=running ci_status=development-pushed
echo "harness: lane $N — development pushed (deploy-dev will auto-trigger)."
