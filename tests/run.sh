#!/usr/bin/env bash
# Run the harness's own test suite: bash tests for the state/path machinery, then
# the dashboard node tests (slug correlation) if vitest is installed.
#   tests/run.sh
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
rc=0

echo "== bash tests =="
for t in "$DIR"/test_*.sh; do
  echo "→ $(basename "$t")"
  bash "$t" || rc=1
done

echo
echo "== node tests (dashboard slug correlation) =="
if [ -x "$DIR/../dashboard/node_modules/.bin/vitest" ]; then
  ( cd "$DIR/../dashboard" && npm test --silent ) || rc=1
else
  echo "  SKIPPED — vitest not installed (run: cd dashboard && npm install)"
fi

echo
[ "$rc" -eq 0 ] && echo "✅ ALL TESTS PASSED" || echo "❌ SOME TESTS FAILED"
exit "$rc"
