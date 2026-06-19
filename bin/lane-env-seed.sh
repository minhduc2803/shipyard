#!/usr/bin/env bash
# Seed/repair a lane's backend/.env. The lane is a git clone, and .env is
# gitignored, so it never arrives via clone — we copy the SOURCE repo's real .env
# (LLM keys, model IDs, JWT_SECRET, flags) and then REWRITE the per-lane keys
# (DATABASE_URL / REDIS_URL / UPLOAD_DIR) to this lane's values so the file is
# correct on its own — not merely masked by lane-up's runtime exports.
#
#   lane-env-seed.sh <N>            # create from source if missing, then fix per-lane keys
#   lane-env-seed.sh <N> --force    # re-copy from source (refresh), then fix per-lane keys
#
# ENV stays whatever the source sets (local) → non-production → wildcard CORS, so
# the lane FE on :300N can call the API on :800N. The real source .env keeps its
# JWT_SECRET (lane-e2e reads the same file, so tokens match the running stack).
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
require_lane "${1:-}"
N="$1"; FORCE="${2:-}"
DIR="$(lane_dir "$N")"
[ -d "$DIR/.git" ] || die "lane $N not bootstrapped"
F="$DIR/backend/.env"
SRC="$SOURCE_REPO/backend/.env"
EX="$DIR/backend/.env.example"

# On a refresh of an EXISTING lane, preserve its current JWT_SECRET so the
# already-booted stack keeps validating tokens (lane-e2e reads it from here) —
# otherwise swapping in the source's secret would 401 a running lane until reboot.
PRESERVE_JWT=""
if [ -f "$F" ] && [ "$FORCE" = "--force" ]; then
  PRESERVE_JWT="$(grep -E '^[[:space:]]*(export[[:space:]]+)?JWT_SECRET=' "$F" 2>/dev/null | tail -1 | sed -E 's/^[^=]*=//')"
fi

if [ ! -f "$F" ] || [ "$FORCE" = "--force" ]; then
  if [ -f "$SRC" ]; then
    cp "$SRC" "$F"; echo "harness: lane $N .env seeded from source repo (real settings/keys)"
  elif [ -f "$EX" ]; then
    cp "$EX" "$F"; echo "harness: WARNING — source .env missing; lane $N .env from .env.example (no LLM key)"
  else
    die "no source .env and no .env.example to seed lane $N"
  fi
fi

# Rewrite the per-lane keys so the FILE matches this lane (not the source/template),
# and restore the preserved JWT_SECRET if we captured one.
DB="$(lane_db_url "$N")" RD="$(lane_redis_url "$N")" UP="$(lane_upload_dir "$N")" PJWT="$PRESERVE_JWT" F="$F" python3 - <<'PY'
import os, re
f = os.environ["F"]
want = {
    "DATABASE_URL": os.environ["DB"],
    "REDIS_URL":    os.environ["RD"],
    "UPLOAD_DIR":   os.environ["UP"],
}
if os.environ.get("PJWT"):
    want["JWT_SECRET"] = os.environ["PJWT"]
lines = open(f).read().splitlines()
seen = set()
for i, line in enumerate(lines):
    m = re.match(r"\s*(?:export\s+)?([A-Z_]+)=", line)
    if m and m.group(1) in want:
        lines[i] = f"{m.group(1)}={want[m.group(1)]}"
        seen.add(m.group(1))
for k, v in want.items():
    if k not in seen:
        lines.append(f"{k}={v}")
open(f, "w").write("\n".join(lines) + "\n")
print("  per-lane keys set: " + ", ".join(sorted(want)))
PY
mkdir -p "$DIR/backend/data/uploads"   # the per-lane UPLOAD_DIR
