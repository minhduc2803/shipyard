#!/usr/bin/env bash
# Print a file from the ACTIVE profile's dir (or nothing if absent). Lets agents
# read profile-provided notes (review-checks.md, tracker-notes.md, …) WITHOUT
# sourcing _common.sh themselves — sourcing breaks in zsh (BASH_SOURCE is
# bash-only), so agents just EXECUTE this (it has a bash shebang).
#   profile-cat.sh <relpath>      e.g.  profile-cat.sh review-checks.md
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
[ -n "${1:-}" ] || exit 0
cat "$PROFILE_DIR/$1" 2>/dev/null || true
