#!/usr/bin/env bash
# Serialize a heavy step across all lanes via a named lock.
#   with-lock.sh <name> -- <command...>
# Names: build | e2e | qc | integration  (any string works).
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

command -v flock >/dev/null 2>&1 || die "flock not found — run: brew install flock"

NAME="${1:?lock name required}"; shift
[ "${1:-}" == "--" ] || die "usage: with-lock.sh <name> -- <command...>"
shift
mkdir -p "$HARNESS_ROOT/locks"
LOCKFILE="$HARNESS_ROOT/locks/$NAME.lock"

# Portable across util-linux flock and macOS `brew install flock` (discoteq):
# hold the lock for the duration of the command, release on exit.
# Bounded wait (LOCK_TIMEOUT, default 30 min): a hung lock-holder produces a
# loud, actionable failure instead of an eternal silent hang. Feature-detect
# `-w` against a probe file; fall back to an unbounded wait if unsupported.
LOCK_TIMEOUT="${LOCK_TIMEOUT:-1800}"
echo "harness: acquiring '$NAME' lock (timeout ${LOCK_TIMEOUT}s; then running: $*)" >&2
if flock -w 1 "$LOCKFILE.probe" true 2>/dev/null; then
  rc=0
  flock -w "$LOCK_TIMEOUT" "$LOCKFILE" "$@" || rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "harness: '$NAME' step exited rc=$rc — either the wrapped command failed," >&2
    echo "harness: or the lock wasn't acquired within ${LOCK_TIMEOUT}s (holder check:" >&2
    echo "harness:   ps aux | grep -Ei 'build|test|playwright|e2e').  Re-run this step." >&2
    exit "$rc"
  fi
else
  exec flock "$LOCKFILE" "$@"
fi
