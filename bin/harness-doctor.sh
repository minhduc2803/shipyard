#!/usr/bin/env bash
# Validate a harness profile is complete enough to run a lane.
#   harness-doctor.sh [profile]     # default: the active PROFILE (config/lanes.env)
# Exit 0 = ready (warnings ok); exit 1 = errors that would break a lane.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

PROF="${1:-$PROFILE}"
PDIR="$HARNESS_ROOT/profiles/$PROF"
echo "harness-doctor: profile '$PROF'  ($PDIR)"
[ -d "$PDIR" ] || die "profile dir not found: $PDIR"

errs=0; warns=0
err(){  echo "  ✗ $*"; errs=$((errs+1)); }
warn(){ echo "  ⚠ $*"; warns=$((warns+1)); }
ok(){   echo "  ✓ $*"; }

# 1. config files
for f in profile.env integrations.env; do
  [ -f "$PDIR/$f" ] && ok "$f" || err "missing $f"
done

# 2. lifecycle hooks: present + not an unimplemented stub
for h in bootstrap migrate seed boot health ci-gate e2e; do
  f="$PDIR/hooks/$h.sh"
  if [ ! -f "$f" ]; then err "missing hook: hooks/$h.sh"; continue; fi
  if grep -q 'TODO — implement' "$f"; then err "hook not implemented: hooks/$h.sh (still the template stub)"; continue; fi
  [ -x "$f" ] || warn "hook not executable: hooks/$h.sh (chmod +x recommended)"
  ok "hook $h"
done

# 3. integrations: if enabled, required fields + the MCP server it needs
# shellcheck disable=SC1091
[ -f "$PDIR/integrations.env" ] && source "$PDIR/integrations.env"
if [ "${TRACKER_ENABLED:-0}" = 1 ]; then
  { [ -n "${TRACKER_URL:-}" ] && [ -n "${TRACKER_MCP:-}" ]; } || warn "tracker on but TRACKER_URL / TRACKER_MCP incomplete"
  echo "  • tracker enabled — register MCP server '${TRACKER_MCP:-?}' in the source project"
fi
if [ "${DEV_QC_ENABLED:-0}" = 1 ]; then
  { [ -n "${DEV_SITE_URL:-}" ] && [ -n "${DEV_QC_MCP:-}" ]; } || warn "dev-qc on but DEV_SITE_URL / DEV_QC_MCP incomplete"
  echo "  • dev-qc enabled — register MCP server '${DEV_QC_MCP:-?}' in the source project"
fi
if [ "${CI_WAIT_ENABLED:-0}" = 1 ]; then
  { [ -n "${CI_REPO:-}" ] && [ -n "${CI_DEPLOY_CONTEXT:-}" ]; } || warn "ci-wait on but CI_REPO / CI_DEPLOY_CONTEXT incomplete"
fi

echo "harness-doctor: $errs error(s), $warns warning(s)"
[ "$errs" = 0 ]
