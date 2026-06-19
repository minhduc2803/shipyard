#!/usr/bin/env bash
# One-time migration of lane state to the per-feature format the dashboard's
# feature-picker needs (so past features correlate with their proof dirs):
#   - legacy flat  state/laneN.json        -> state/laneN/<slug>.json + .active
#   - mangled slug development+feat-X.json  -> X.json   (re-derived from .branch)
#   - empty .active with one feature        -> point it at that feature
# <slug> is derived from the state's `branch` field (development+feat/X | feat/X)
# the SAME way the canonical slug is formed, so it matches the proof dir. Backs up
# state/ first. Idempotent — safe to re-run.
#   state-migrate.sh [N | --all]     (default: --all)
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

BACKUP="$HARNESS_ROOT/state.bak.$(date +%Y%m%d-%H%M%S)"
cp -R "$HARNESS_ROOT/state" "$BACKUP"
echo "harness: backed up state/ -> $BACKUP"

migrate_one() {
  local n="$1"
  python3 - "$n" "$HARNESS_ROOT/state/lane$n" "$HARNESS_ROOT/state/lane$n.json" "$INTEGRATION_BRANCH" "$BRANCH_PREFIX" <<'PY'
import json, os, re, sys
n, dir_, flat, integ, prefix = sys.argv[1:6]

def slugify(branch):
    s = branch or ''
    s = re.sub(r'^' + re.escape(integ) + r'\+', '', s)   # strip "development+"
    if s.startswith(prefix): s = s[len(prefix):]         # strip "feat/"
    s = s.replace('/', '-').replace(' ', '-')
    return re.sub(r'[^A-Za-z0-9._-]', '', s)

def load(p):
    try: return json.load(open(p))
    except Exception: return {}

os.makedirs(dir_, exist_ok=True)
ap = os.path.join(dir_, '.active')
active = (open(ap).read().strip() if os.path.exists(ap) else '')
notes = []

# 1) legacy flat file -> per-feature
if os.path.isfile(flat):
    d = load(flat); slug = slugify(d.get('branch', ''))
    if slug:
        tgt = os.path.join(dir_, slug + '.json')
        if not os.path.exists(tgt): json.dump(d, open(tgt, 'w'), indent=2)
        active = slug; notes.append(f'flat -> {slug}.json')
    else:
        tgt = os.path.join(dir_, '_pending.json')
        if not os.path.exists(tgt): json.dump(d, open(tgt, 'w'), indent=2)
        active = ''; notes.append('flat -> _pending.json (idle)')
    os.remove(flat)

# 2) re-derive each per-feature file's slug from its branch; rename if mangled
for fn in [f for f in os.listdir(dir_) if f.endswith('.json') and f != '_pending.json']:
    d = load(os.path.join(dir_, fn)); want = slugify(d.get('branch', '')) or fn[:-5]
    if want != fn[:-5] and not os.path.exists(os.path.join(dir_, want + '.json')):
        os.rename(os.path.join(dir_, fn), os.path.join(dir_, want + '.json'))
        notes.append(f'{fn} -> {want}.json')
        if active in (fn[:-5], ''): active = want

# 3) empty .active but exactly one real feature -> point at it
if not active:
    reals = [f[:-5] for f in os.listdir(dir_) if f.endswith('.json') and f != '_pending.json']
    if len(reals) == 1: active = reals[0]; notes.append(f'.active -> {reals[0]}')

open(ap, 'w').write(active)
print(f'  lane{n}: ' + ('; '.join(notes) if notes else 'ok (already per-feature)'))
PY
}

if [ -n "${1:-}" ] && [ "$1" != "--all" ]; then
  require_lane "$1"; migrate_one "$1"
else
  for n in $(discover_lanes); do migrate_one "$n"; done
fi
echo "harness: state migration done. (restore: rm -rf state && mv $BACKUP state)"
