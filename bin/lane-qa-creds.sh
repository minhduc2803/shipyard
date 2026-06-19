#!/usr/bin/env bash
# Write a lane's dev-site QA account to <lane>/.harness-qa.env (git-excluded).
# This file is the SINGLE source of truth for the dev-qc account — no email
# format is assumed or derived anywhere else in the harness.
#
#   lane-qa-creds.sh <N> [--force]
#
# Interactive (a TTY): prompts for email + password (password defaults to the
# shared DEV_QC_PASSWORD from secrets.env — press Enter to use it).
# Non-interactive (dashboard/background): set LANE_DEV_QC_EMAIL / LANE_DEV_QC_PASSWORD
# in the environment; otherwise the email is left blank (with a warning) and the
# shared password is used. Re-runnable: keeps complete existing creds unless --force.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
require_lane "${1:-}"
N="$1"; FORCE="${2:-}"
DIR="$(lane_dir "$N")"
F="$DIR/.harness-qa.env"
SHARED_PW="${DEV_QC_PASSWORD:-}"   # shared default from secrets.env (via _common)

# Re-runnable: keep complete existing creds unless --force.
if [ -f "$F" ] && [ "$FORCE" != "--force" ]; then
  EXIST_EMAIL="$(. "$F" 2>/dev/null; echo "${DEV_QC_EMAIL:-}")"
  EXIST_PW="$(. "$F" 2>/dev/null; echo "${DEV_QC_PASSWORD:-}")"
  if [ -n "$EXIST_EMAIL" ] && [ -n "$EXIST_PW" ]; then
    echo "harness: lane $N dev-QC creds already set ($EXIST_EMAIL) — keeping (use --force to change)"
    exit 0
  fi
fi

email=""; password=""
if [ -t 0 ] && [ -t 1 ]; then
  read -r  -p "harness: dev-QC account email for lane $N: " email
  read -rs -p "harness: dev-QC password for lane $N (Enter = shared default): " password; echo
  password="${password:-$SHARED_PW}"
else
  email="${LANE_DEV_QC_EMAIL:-}"
  password="${LANE_DEV_QC_PASSWORD:-$SHARED_PW}"
fi

mkdir -p "$DIR"
cat > "$F" <<EOF
# Per-lane dev-site QA account (the dev site) — source of truth for the
# dev-qc agent's login. Written by lane-qa-creds.sh; git-excluded. Edit freely.
export DEV_QC_EMAIL="$email"
export DEV_QC_PASSWORD="$password"
EOF
grep -qxF ".harness-qa.env" "$DIR/.git/info/exclude" 2>/dev/null || echo ".harness-qa.env" >> "$DIR/.git/info/exclude"

if [ -n "$email" ]; then
  echo "harness: wrote dev-QC creds for lane $N ($email) -> $F"
else
  echo "harness: WARNING — lane $N dev-QC email is BLANK. Set it before dev-QC runs:" >&2
  echo "         edit $F (DEV_QC_EMAIL=...), then: bin/lane-qa-login.sh $N dev" >&2
fi
