#!/usr/bin/env bash
# Seed a logged-in session into a lane's Playwright QA Chromium profile so the
# QC agents open already authenticated — fixing profile-session expiry WITHOUT
# ever routing a password through an agent's context (passwords are read here as
# shell env vars and handed to the headless login helper; no LLM sees them).
#
#   lane-qa-login.sh <N> [dev|local|ticketer|all]   # default: dev
#   lane-qa-login.sh --all [dev|local|ticketer|all] # every bootstrapped lane
#
# Targets (each seeds the matching Chromium profile; password read from env, never an agent):
#   dev      -> the dev site (DEV_SITE_URL from the profile), the lane's dev-QC account
#               (email + password from <lane>/.harness-qa.env — the source of truth),
#               profile qa-dev  (used by the dev-qc agent)
#   local    -> http://localhost:300<N> (app) / :800<N> (api), the seeded lane account
#               (SEED_USER_EMAIL/SEED_USER_PASSWORD from secrets.env),
#               profile qa-local (used by the qc-local agent) — requires the lane stack UP.
#   ticketer -> the tracker (TRACKER_URL from the profile), account TRACKER_EMAIL/TRACKER_PASSWORD
#               (secrets.env), profile ticketer (used by the ticketer agent).
#   all      -> dev + ticketer + local (local self-skips if the stack is down).
#
# IMPORTANT: the matching MCP browser must NOT be open on the profile while this
# runs (Chromium locks the user-data-dir). At bootstrap that's fine; on-demand,
# the agent closes its browser (browser_close) first.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

seed_dev() {
  local N="$1" DIR profile email="" password=""
  DIR="$(lane_dir "$N")"
  profile="$DIR/.playwright-mcp/profiles/qa-dev"; mkdir -p "$profile"
  if [ -f "$DIR/.harness-qa.env" ]; then
    # shellcheck disable=SC1091
    source "$DIR/.harness-qa.env"; email="${DEV_QC_EMAIL:-}"; password="${DEV_QC_PASSWORD:-}"
  fi
  password="${password:-${DEV_QC_PASSWORD:-}}"   # fall back to shared secrets.env password
  [ -n "$email" ] || die "no DEV_QC_EMAIL for lane $N — run 'bin/lane-qa-creds.sh $N' (or edit $DIR/.harness-qa.env)"
  [ -n "$password" ] || die "no DEV_QC_PASSWORD for lane $N (set $DIR/.harness-qa.env or config/secrets.env)"
  echo "harness: seeding DEV session for lane $N ($email) ..."
  ( cd "$DIR/frontend" && FRONTEND_DIR="$DIR/frontend" USER_DATA_DIR="$profile" \
      API_BASE="${DEV_SITE_URL:?DEV_SITE_URL not set (profile integrations.env)}" APP_ORIGIN="$DEV_SITE_URL" \
      EMAIL="$email" PASSWORD="$password" \
      "$HARNESS_ROOT/bin/mcp-node-exec.sh" node "$HARNESS_ROOT/bin/lane-qa-login.cjs" )
}

seed_local() {
  local N="$1" DIR profile api app
  DIR="$(lane_dir "$N")"
  profile="$DIR/.playwright-mcp/profiles/qa-local"; mkdir -p "$profile"
  api="http://localhost:$(lane_api_port "$N")"; app="$(lane_fe_url "$N")"
  [ -n "${SEED_USER_PASSWORD:-}" ] || die "no SEED_USER_PASSWORD (set config/secrets.env)"
  if ! curl -sf -o /dev/null --max-time 5 "$api/api/v1/health" 2>/dev/null \
     && ! curl -sf -o /dev/null --max-time 5 "$api/docs" 2>/dev/null; then
    echo "harness: SKIP local seed for lane $N — stack not reachable at $api (boot it first: lane-up.sh $N)"; return 0
  fi
  echo "harness: seeding LOCAL session for lane $N ($SEED_USER_EMAIL @ $app) ..."
  ( cd "$DIR/frontend" && FRONTEND_DIR="$DIR/frontend" USER_DATA_DIR="$profile" \
      API_BASE="$api" APP_ORIGIN="$app" \
      EMAIL="$SEED_USER_EMAIL" PASSWORD="$SEED_USER_PASSWORD" \
      "$HARNESS_ROOT/bin/mcp-node-exec.sh" node "$HARNESS_ROOT/bin/lane-qa-login.cjs" )
}

seed_ticketer() {
  local N="$1" DIR profile
  DIR="$(lane_dir "$N")"
  profile="$DIR/.playwright-mcp/profiles/ticketer"; mkdir -p "$profile"
  [ -n "${TRACKER_EMAIL:-}" ] && [ -n "${TRACKER_PASSWORD:-}" ] \
    || die "no TRACKER_EMAIL/TRACKER_PASSWORD (set config/secrets.env)"
  echo "harness: seeding TRACKER session for lane $N ($TRACKER_EMAIL) ..."
  ( cd "$DIR/frontend" && FRONTEND_DIR="$DIR/frontend" USER_DATA_DIR="$profile" \
      TRACKER_URL="${TRACKER_URL:?TRACKER_URL not set (profile integrations.env)}" \
      EMAIL="$TRACKER_EMAIL" PASSWORD="$TRACKER_PASSWORD" \
      "$HARNESS_ROOT/bin/mcp-node-exec.sh" node "$HARNESS_ROOT/bin/lane-tracker-login.cjs" )
}

seed_lane() {
  local N="$1" target="$2"
  [ -d "$(lane_dir "$N")/.git" ] || die "lane $N not bootstrapped"
  case "$target" in
    dev)      seed_dev "$N" ;;
    local)    seed_local "$N" ;;
    ticketer) seed_ticketer "$N" ;;
    all)      seed_dev "$N"; seed_ticketer "$N"; seed_local "$N" ;;
    *) die "unknown target '$target' (dev|local|ticketer|all)" ;;
  esac
}

if [ "${1:-}" == "--all" ]; then
  TARGET="${2:-dev}"; rc=0
  for n in $(discover_lanes); do seed_lane "$n" "$TARGET" || rc=1; done
  exit $rc
else
  require_lane "${1:-}"
  seed_lane "$1" "${2:-dev}"
fi
