#!/usr/bin/env bash
# Spec stages 3-4: merge the lane's feature branch onto a fresh local
# `development` and (re)boot the lane stack so e2e + manual QC run on the
# INTEGRATED tree. Does NOT push. The feature branch is left intact for the PR.
#   lane-integrate.sh <N> [feature_branch]                (default: current branch)
#   lane-integrate.sh <N> --continue [feature_branch]     finish after the session
#       resolved a merge conflict and committed the merge (migrate + boot only)
# Exit 4 = MERGE CONFLICT, left IN PLACE on purpose: resolve the conflicted
# files (keep development's behavior for unrelated code, the feature's intent
# where they overlap), `git add` the conflicted files, `git commit --no-edit`,
# then run `lane-integrate.sh <N> --continue`. Conflicts are normal work — the
# lane stays status=running, NOT blocked.
# Export MOCK_AGENT=true RATE_LIMIT_ENABLED=false before calling to boot the
# test stack in CI-mode (so e2e/QC don't need real LLM keys).
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
require_lane "${1:-}"
N="$1"; DIR="$(lane_dir "$N")"
[ -d "$DIR/.git" ] || die "lane $N not bootstrapped"

MODE=fresh
if [ "${2:-}" == "--continue" ]; then
  MODE=continue
  FEATURE="${3:-}"
else
  FEATURE="${2:-$(git -C "$DIR" rev-parse --abbrev-ref HEAD)}"
  [ "$FEATURE" != "$INTEGRATION_BRANCH" ] || die "current branch is '$INTEGRATION_BRANCH'; pass a feature branch to integrate"
fi

if [ "$MODE" == "fresh" ]; then
  "$HARNESS_ROOT/bin/lane-down.sh" "$N" || true

  echo "harness: integrating '$FEATURE' onto fresh development (lane $N) ..."
  git -C "$DIR" fetch origin --prune
  git -C "$DIR" checkout "$INTEGRATION_BRANCH"
  git -C "$DIR" reset --hard "origin/$INTEGRATION_BRANCH"
  if ! git -C "$DIR" merge --no-edit "$FEATURE"; then
    "$HARNESS_ROOT/bin/state.sh" "$N" set stage=integrate-conflict status=running \
      notes="merge conflict: $FEATURE vs origin/development — resolve, commit, then --continue"
    echo "harness: lane $N — MERGE CONFLICT (left in place)." >&2
    echo "harness: resolve the conflicted files, then:" >&2
    echo "harness:   git -C '$DIR' add <resolved files> && git -C '$DIR' commit --no-edit" >&2
    echo "harness:   $HARNESS_ROOT/bin/lane-integrate.sh $N --continue $FEATURE" >&2
    exit 4
  fi
else
  echo "harness: continuing lane $N integration after conflict resolution ..."
  [ "$(git -C "$DIR" rev-parse --abbrev-ref HEAD)" == "$INTEGRATION_BRANCH" ] \
    || die "--continue: lane $N is not on development"
  [ -z "$(git -C "$DIR" ls-files -u)" ] \
    || die "--continue: unresolved conflicts remain (git -C $DIR status)"
  [ ! -f "$DIR/.git/MERGE_HEAD" ] \
    || die "--continue: merge not committed yet — git -C $DIR commit --no-edit"
  if [ -z "$FEATURE" ]; then
    FEATURE="$(git -C "$DIR" log -1 --format=%s | sed -n "s/^Merge branch '\([^']*\)'.*/\1/p")"
    [ -n "$FEATURE" ] || FEATURE="feature"
  fi
fi

write_lane_markers "$N" "$DIR"

echo "harness: applying migrations to $(lane_db "$N") ..."
run_hook "$N" migrate
echo "harness: rebooting lane $N on the integrated tree ..."
"$HARNESS_ROOT/bin/lane-up.sh" "$N"
"$HARNESS_ROOT/bin/state.sh" "$N" set stage=integrated-testing status=running branch="$INTEGRATION_BRANCH+$FEATURE"
echo "harness: lane $N — '$FEATURE' integrated onto development; stack live at $(lane_fe_url "$N")."
