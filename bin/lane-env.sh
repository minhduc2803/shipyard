#!/usr/bin/env bash
# Emit the lane's runtime env + integration toggles as eval-able `export` lines,
# OR check a single integration toggle (--check NAME -> exit 0/1).
#
# WHY THIS EXISTS: the Bash tool's session shell is zsh, and `source bin/_common.sh`
# under zsh mis-resolves HARNESS_ROOT — BASH_SOURCE is a bash-only array, so it is
# empty in zsh, dirname falls back to the cwd, and the `/harness` segment is dropped.
# config/lanes.env is then never found and (zsh's errexit not firing on the failed
# source) PROFILE SILENTLY degrades to `_template`, where every integration reads OFF.
# A pipeline that trusts that reading skips the ticket / dev-QC / ci-wait stages with
# no error. The bin/* scripts are immune because they EXECUTE under their bash shebang
# (BASH_SOURCE is populated); agents must do the same instead of sourcing _common.sh
# themselves — exactly like profile-cat.sh. Self-contained usage from a skill:
#   eval "$("$HARNESS/bin/lane-env.sh" "$N")"               # re-establish env + toggles
#   "$HARNESS/bin/lane-env.sh" "$N" --check dev_qc && ...   # gate a stage on an integration
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
require_lane "${1:-}"
N="$1"; shift || true

# --check NAME: exit status mirrors harness_integration_enabled (0 = on, 1 = off).
if [ "${1:-}" = "--check" ]; then
  harness_integration_enabled "${2:-}"
  exit $?
fi

# Default: the per-lane runtime contract run_hook exports, computed without running a
# hook, plus PROFILE/config and the integration toggles + their detail fields.
export LANE="$N" LANE_DIR="$(lane_dir "$N")"
export API_PORT="$(lane_api_port "$N")" FE_PORT="$(lane_fe_port "$N")"
export DATABASE_URL="$(lane_db_url "$N")" REDIS_URL="$(lane_redis_url "$N")"
export UPLOAD_DIR="$(lane_upload_dir "$N")" DB_NAME="$(lane_db "$N")"
export API_BASE="$(lane_api_base "$N")" FE_URL="$(lane_fe_url "$N")"
export RUN_DIR="$(lane_run_dir "$N")" LOG_DIR="$(lane_log_dir "$N")"

# Single-quote each value so the output is safe to `eval` in bash OR zsh.
q() { printf "'%s'" "${1//\'/\'\\\'\'}"; }
emit() { local name val; for name in "$@"; do eval "val=\${$name-}"; printf 'export %s=%s\n' "$name" "$(q "$val")"; done; }

emit LANE LANE_DIR API_PORT FE_PORT DATABASE_URL REDIS_URL UPLOAD_DIR DB_NAME \
     API_BASE FE_URL RUN_DIR LOG_DIR \
     PROFILE PROFILE_DIR SOURCE_REPO HARNESS_ROOT WORKER_QUEUES COMPOSE_FILE \
     PG_HOST PG_PORT PG_USER PG_PASS REDIS_HOST REDIS_PORT DB_PREFIX \
     SEED_USER_EMAIL SEED_USER_PASSWORD \
     TRACKER_ENABLED TRACKER_PROVIDER TRACKER_URL TRACKER_PROJECT TRACKER_STATUS TRACKER_ASSIGNEE TRACKER_MCP \
     DEV_QC_ENABLED DEV_SITE_URL DEV_QC_MCP \
     CI_WAIT_ENABLED CI_PROVIDER CI_REPO CI_DEPLOY_CONTEXT
