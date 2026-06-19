#!/usr/bin/env bash
# One-time per lane: clone the repo, install deps, migrate the lane DB, seed user.
# Re-runnable: skips clone/deps if already present.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
require_lane "${1:-}"
N="$1"
DIR="$(lane_dir "$N")"
ORIGIN_URL="${ORIGIN_URL:-$(git -C "$SOURCE_REPO" remote get-url origin)}"

# Progress → lane state, but ONLY when provisioning a NEW lane (lane-add sets
# HARNESS_PROVISION_STATE=1). Standalone re-runs on a live lane don't touch state.
pstate(){ [ -n "${HARNESS_PROVISION_STATE:-}" ] && "$HARNESS_ROOT/bin/state.sh" "$N" set stage="$1" status=provisioning >/dev/null 2>&1 || true; }

pstate cloning
if [ ! -d "$DIR/.git" ]; then
  echo "harness: cloning into $DIR (fast local clone) ..."
  git clone "$SOURCE_REPO" "$DIR"
  echo "harness: pointing origin at $ORIGIN_URL ..."
  git -C "$DIR" remote set-url origin "$ORIGIN_URL"
fi

echo "harness: syncing with origin + checking out development ..."
git -C "$DIR" fetch origin --prune
git -C "$DIR" checkout "$INTEGRATION_BRANCH"
git -C "$DIR" reset --hard "origin/$INTEGRATION_BRANCH"

echo "harness: marking lane id + harness root ..."
write_lane_markers "$N" "$DIR"

echo "harness: seeding backend/.env from source + per-lane DB/Redis/Upload ..."
"$HARNESS_ROOT/bin/lane-env-seed.sh" "$N" || echo "harness: WARNING — .env seed failed; run bin/lane-env-seed.sh $N"

pstate setting-creds
echo "harness: setting the lane's dev-QC account (.harness-qa.env) ..."
"$HARNESS_ROOT/bin/lane-qa-creds.sh" "$N" || echo "harness: WARNING — could not set dev-QC creds; run bin/lane-qa-creds.sh $N"

pstate installing-deps
echo "harness: installing deps (profile hook) ..."
run_hook "$N" bootstrap

echo "harness: ensuring db $(lane_db "$N") exists ..."
if ! docker compose -f "$COMPOSE_FILE" exec -T "$DB_SERVICE" \
     psql -U "$PG_USER" -tAc "SELECT 1 FROM pg_database WHERE datname='$(lane_db "$N")'" | grep -q 1; then
  docker compose -f "$COMPOSE_FILE" exec -T "$DB_SERVICE" createdb -U "$PG_USER" "$(lane_db "$N")"
fi

pstate migrating
echo "harness: migrating $(lane_db "$N") (profile hook) ..."
run_hook "$N" migrate

pstate seeding-user
echo "harness: seeding user $SEED_USER_EMAIL (profile hook) ..."
run_hook "$N" seed

pstate mcp-sync
echo "harness: syncing MCP servers (playwright/qa/ticketer) into the lane ..."
"$HARNESS_ROOT/bin/lane-mcp-sync.sh" "$N" || echo "harness: WARNING — MCP sync failed; run bin/lane-mcp-sync.sh $N manually"

pstate installing-agents
echo "harness: installing per-lane agents with embedded credentials (.claude/agents, gitignored) ..."
"$HARNESS_ROOT/bin/lane-agents-install.sh" "$N" || echo "harness: WARNING — per-lane agent install failed; run bin/lane-agents-install.sh $N"

pstate qa-login
echo "harness: pre-seeding QA sessions (dev + tracker; local self-skips until the stack is up) ..."
"$HARNESS_ROOT/bin/lane-qa-login.sh" "$N" all || echo "harness: WARNING — a QA session seed failed (does the lane's dev-QC account in $DIR/.harness-qa.env exist on dev? are TRACKER_* set?). Re-run: bin/lane-qa-login.sh $N all"

echo "harness: lane $N bootstrapped at $DIR"
