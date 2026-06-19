#!/usr/bin/env bash
# Shared helpers: load config + derive per-lane values. Source this; don't exec.
set -euo pipefail

_HARNESS_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_ROOT="${HARNESS_ROOT:-$(cd "$_HARNESS_BIN/.." && pwd)}"
# shellcheck disable=SC1091
source "$HARNESS_ROOT/config/lanes.env"

# Active profile: stack-shape config in profiles/<PROFILE>/profile.env, with
# harness defaults below so a missing key never breaks an existing lane.
# The real PROFILE comes from config/lanes.env (sourced above); this fallback is
# only the `set -u` guard. It names the template — never a real project — so a
# mis-configured install degrades to the stubs harness-doctor flags, not silently
# to some other team's stack.
PROFILE="${PROFILE:-_template}"
PROFILE_DIR="${PROFILE_DIR:-$HARNESS_ROOT/profiles/$PROFILE}"
# shellcheck disable=SC1091
[ -f "$PROFILE_DIR/profile.env" ] && source "$PROFILE_DIR/profile.env"
DB_URL_SCHEME="${DB_URL_SCHEME:-postgresql+asyncpg}"
API_PATH="${API_PATH:-/api/v1}"
UPLOAD_SUBDIR="${UPLOAD_SUBDIR:-backend/data/uploads}"
BACKEND_DIR="${BACKEND_DIR:-backend}"
FRONTEND_DIR="${FRONTEND_DIR:-frontend}"
DB_SERVICE="${DB_SERVICE:-postgres}"
COMPOSE_SERVICES="${COMPOSE_SERVICES:-postgres redis adminer}"
BASE_BRANCH="${BASE_BRANCH:-main}"
INTEGRATION_BRANCH="${INTEGRATION_BRANCH:-development}"
BRANCH_PREFIX="${BRANCH_PREFIX:-feat/}"
# Optional org integrations (tracker / dev-qc / ci-wait); off unless the profile enables them.
# shellcheck disable=SC1091
[ -f "$PROFILE_DIR/integrations.env" ] && source "$PROFILE_DIR/integrations.env"
# harness_integration_enabled tracker|dev_qc|ci_wait  -> exit 0 if that integration is on
harness_integration_enabled() {
  case "$1" in
    tracker) [ "${TRACKER_ENABLED:-0}" = 1 ];;
    dev_qc)  [ "${DEV_QC_ENABLED:-0}" = 1 ];;
    ci_wait) [ "${CI_WAIT_ENABLED:-0}" = 1 ];;
    *) return 1;;
  esac
}

die() { echo "harness: $*" >&2; exit 1; }

# Lanes are numbered 1-9: ports are 8000+N / 3000+N and the Redis index is N
# (Redis ships 16 logical DBs, and single-digit lanes keep the port scheme sane).
require_lane() {
  local n="${1:-}"
  [[ "$n" =~ ^[1-9]$ ]] || die "lane must be 1-9 (got '${n:-}')"
}

# Print the lane numbers that exist on disk (a laneN dir with a .git), sorted.
discover_lanes() {
  local d out=""
  for d in "$LANES_ROOT"/lane[1-9]; do
    [ -d "$d/.git" ] && out="$out ${d##*lane}"
  done
  echo "$out" | xargs || true
}

lane_dir()       { echo "$LANES_ROOT/lane$1"; }
lane_api_port()  { echo "$((API_BASE_PORT + $1))"; }
lane_fe_port()   { echo "$((FE_BASE_PORT + $1))"; }
lane_db()        { echo "${DB_PREFIX}$1"; }
lane_redis_idx() { echo "$1"; }
lane_db_url()    { echo "${DB_URL_SCHEME}://$PG_USER:$PG_PASS@$PG_HOST:$PG_PORT/$(lane_db "$1")"; }
lane_redis_url() { echo "redis://$REDIS_HOST:$REDIS_PORT/$(lane_redis_idx "$1")"; }
lane_api_base()  { echo "http://localhost:$(lane_api_port "$1")${API_PATH}"; }
lane_fe_url()    { echo "http://localhost:$(lane_fe_port "$1")"; }
lane_upload_dir(){ echo "$(lane_dir "$1")/$UPLOAD_SUBDIR"; }
lane_state_file(){
  local dir="$HARNESS_ROOT/state/lane$1"
  # Old flat-file format: return it until migrated by state.sh init
  if [ ! -d "$dir" ] && [ -f "$dir.json" ]; then
    echo "$dir.json"; return
  fi
  # New per-feature format: read .active pointer
  local active=""
  [ -f "$dir/.active" ] && active="$(cat "$dir/.active" 2>/dev/null)" && active="${active%"${active##*[![:space:]]}"}"
  if [ -n "$active" ]; then
    echo "$dir/$active.json"
  else
    echo "$dir/_pending.json"
  fi
}
lane_run_dir()   { echo "$HARNESS_ROOT/run/lane$1"; }
lane_log_dir()   { echo "$HARNESS_ROOT/logs/lane$1"; }

# Write the lane's marker file (.harness-lane = lane number) and git-exclude it.
# Idempotent. The harness PATH is NOT stored per-lane — it's baked into the
# installed skills/agents at install time via the @@HARNESS_ROOT@@ placeholder
# (the single source of truth); lane paths are resolved at runtime with $(pwd).
write_lane_markers() {
  local n="$1" dir="$2" m
  echo "$n" > "$dir/.harness-lane"
  # Local git-excludes (the clone's .git/info/exclude, NOT the app's tracked
  # .gitignore) for the harness's own artifacts in the app clone:
  #   .harness-lane — the lane marker;
  #   /proof        — the clone-root proof entry. It is now intentionally a SYMLINK
  #     to .playwright-mcp/proof (see ensure_proof_link); no trailing slash so the
  #     exclude matches a symlink, dir, OR file named proof at the root.
  for m in .harness-lane "/proof"; do
    grep -qxF "$m" "$dir/.git/info/exclude" 2>/dev/null || echo "$m" >> "$dir/.git/info/exclude"
  done
  ensure_proof_link "$dir"
}

# Converge the proof root onto <lane>/.playwright-mcp/proof — the one place the
# dashboard reads. A screenshot taken before the MCP's pinned --output-dir is in
# effect (a session that synced .mcp.json but hasn't restarted), or a Write-tool
# path of `proof/...`, otherwise lands in the clone-root `proof/` and is invisible
# to the dashboard — stranding QC shots and the ticket REPORT.html (exactly the
# 🎫-link-missing bug). Making clone-root `proof` a SYMLINK to the canonical root
# makes EVERY proof write converge there regardless of path convention or
# --output-dir. Idempotent; safe direction — the real store is .playwright-mcp/proof
# and the symlink is the disposable side (the opposite direction caused data loss
# before). A pre-existing real proof/ dir is merged into the canonical root (no
# clobber) before linking, so older lanes' stranded proof is recovered in place.
ensure_proof_link() {
  local dir="$1" canon="$1/.playwright-mcp/proof" stray="$1/proof"
  mkdir -p "$canon"
  if [ -L "$stray" ]; then
    [ "$(readlink "$stray")" = ".playwright-mcp/proof" ] || { rm -f "$stray"; ln -s ".playwright-mcp/proof" "$stray"; }
  elif [ -d "$stray" ]; then
    cp -Rn "$stray"/. "$canon"/ 2>/dev/null || true   # merge stray -> canonical (no clobber)
    rm -rf "$stray"                                    # contents fully merged above; gitignored
    ln -s ".playwright-mcp/proof" "$stray"
  elif [ ! -e "$stray" ]; then
    ln -s ".playwright-mcp/proof" "$stray"
  fi
}

# --- Profile seam ---------------------------------------------------------
# The active profile supplies the stack-specific lifecycle hooks; the harness
# stays generic and calls them via run_hook with a documented env contract.
# (PROFILE / PROFILE_DIR are resolved above, right after sourcing lanes.env.)

# Background a long-lived service with FULLY detached stdio + record its pid/log
# where lane-down.sh / lane-status.sh look. The detachment MUST stay (it is the
# fix for the 2026-06-11 stage-4 stalls: an attached child holds the caller's
# stdout pipe open and `... | tail` never sees EOF). Use inside a boot hook:
#   harness_spawn <name> <workdir> <cmd> [args...]
harness_spawn() {
  local name="$1" wd="$2"; shift 2
  ( cd "$wd" || exit 1
    nohup "$@" >"$LOG_DIR/$name.log" 2>&1 </dev/null &
    echo $! >"$RUN_DIR/$name.pid"
  ) </dev/null >/dev/null 2>&1
}

# Run a profile hook for lane N with the stable env contract exported.
#   run_hook <N> <hook-name> [args...]
run_hook() {
  local n="$1" name="$2"; shift 2
  require_lane "$n"
  local hook="$PROFILE_DIR/hooks/$name.sh"
  [ -f "$hook" ] || die "profile '$PROFILE' ($PROFILE_DIR) has no hook '$name.sh'"
  export LANE="$n" LANE_DIR="$(lane_dir "$n")"
  export API_PORT="$(lane_api_port "$n")" FE_PORT="$(lane_fe_port "$n")"
  export DATABASE_URL="$(lane_db_url "$n")" REDIS_URL="$(lane_redis_url "$n")"
  export UPLOAD_DIR="$(lane_upload_dir "$n")" DB_NAME="$(lane_db "$n")"
  export API_BASE="$(lane_api_base "$n")" FE_URL="$(lane_fe_url "$n")"
  export RUN_DIR="$(lane_run_dir "$n")" LOG_DIR="$(lane_log_dir "$n")"
  export PROFILE PROFILE_DIR SOURCE_REPO HARNESS_ROOT
  export WORKER_QUEUES COMPOSE_FILE PG_HOST PG_PORT PG_USER PG_PASS \
         REDIS_HOST REDIS_PORT DB_PREFIX SEED_USER_EMAIL SEED_USER_PASSWORD
  export -f harness_spawn die
  bash "$hook" "$@"
}

# Background heartbeat ticker for long-running steps so the dashboard doesn't
# false-flag a working lane as STALLED. Usage: hb_start <N>; trap hb_stop EXIT
# Stdio is detached (so it can never hold a caller's pipe open) and it
# self-terminates if its owning script dies without running the EXIT trap.
hb_start() {
  local lane="$1" owner=$$
  (
    while kill -0 "$owner" 2>/dev/null; do
      "$HARNESS_ROOT/bin/state.sh" "$lane" set >/dev/null 2>&1 || break
      sleep 45 || break
    done
  ) </dev/null >/dev/null 2>&1 &
  _HB_PID=$!
}
hb_stop() { [ -n "${_HB_PID:-}" ] && kill "$_HB_PID" 2>/dev/null || true; _HB_PID=""; }
