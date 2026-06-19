import fs from 'fs';
import path from 'path';
import { LANES_ROOT, STATE_DIR, FE_BASE_PORT, API_BASE_PORT, STALL_SEC } from './config.js';
import { harnessConfig } from './config.js';
import { git } from './git.js';
import { portUp } from './ports.js';

export const STAGE_ORDER = [
  'assigned', 'intake', 'plan', 'implementing', 'pre-push-gate',
  'e2e-feature', 'e2e-feature-passed',
  'integrated-testing', 'integrate-conflict', 'booting', 'live', 'dev-gate', 'e2e', 'e2e-passed',
  'review', 'qc-plan', 'qc', 'gate',
  'pushing-development', 'push-conflict', 'pushed-development', 'pr-open', 'qc-dev', 'ticketed',
  'reported', 'watching-pr', 'done',
];

export function discoverLanes() {
  const nums = new Set();
  try {
    for (const d of fs.readdirSync(LANES_ROOT)) {
      if (/^lane[1-9]$/.test(d) && fs.existsSync(path.join(LANES_ROOT, d, '.git')))
        nums.add(parseInt(d[4], 10));
    }
  } catch { /* dir not found */ }
  try {
    for (const f of fs.readdirSync(STATE_DIR)) {
      if (/^lane[1-9]\.json$/.test(f))
        nums.add(parseInt(f[4], 10));
      if (/^lane[1-9]$/.test(f) && fs.statSync(path.join(STATE_DIR, f)).isDirectory())
        nums.add(parseInt(f[4], 10));
    }
  } catch { /* dir not found */ }
  return [...nums].sort();
}

async function readLane(n) {
  const lane = {
    lane: n, stage: 'no-state', status: 'idle', feature_title: '',
    branch: '', pr_url: '', ticket_url: '', gate_decision: '', ci_status: '',
    qc_dev: '', mode: 'ship',
    manual_test_url: `http://localhost:${FE_BASE_PORT + n}`,
    last_heartbeat: '', notes: '',
  };

  const stateDir = path.join(STATE_DIR, `lane${n}`);
  const flatFile = path.join(STATE_DIR, `lane${n}.json`);
  let stateFile = null;
  if (fs.existsSync(stateDir) && fs.statSync(stateDir).isDirectory()) {
    let active = '';
    try { active = fs.readFileSync(path.join(stateDir, '.active'), 'utf8').trim(); } catch { /* no .active */ }
    stateFile = active ? path.join(stateDir, `${active}.json`) : path.join(stateDir, '_pending.json');
  } else if (fs.existsSync(flatFile)) {
    stateFile = flatFile;
  }
  if (stateFile && fs.existsSync(stateFile)) {
    try {
      Object.assign(lane, JSON.parse(fs.readFileSync(stateFile, 'utf8')));
    } catch (e) {
      lane.notes = `state parse error: ${e.message}`;
    }
  }

  lane.git_branch = git(n, 'rev-parse', '--abbrev-ref', 'HEAD') || '(not bootstrapped)';
  const head = git(n, 'log', '-1', '--format=%h %s');
  lane.head = head.length > 72 ? head.slice(0, 72) + '…' : head;

  const [apiUp, feUp] = await Promise.all([
    portUp(API_BASE_PORT + n),
    portUp(FE_BASE_PORT + n),
  ]);
  lane.api_up = apiUp;
  lane.fe_up = feUp;

  const stage = lane.stage || '';
  const idx = STAGE_ORDER.indexOf(stage);
  lane.progress = idx >= 0 ? Math.round((idx + 1) / STAGE_ORDER.length * 100) : null;

  let age = null;
  let stalled = false;
  const hb = lane.last_heartbeat;
  if (hb) {
    try {
      const t = new Date(hb);
      if (!isNaN(t.getTime())) age = (Date.now() - t.getTime()) / 1000;
    } catch { /* bad date */ }
  }
  if (lane.status === 'running' && age !== null && age > STALL_SEC) stalled = true;
  lane.heartbeat_age_sec = age !== null ? Math.round(age) : null;
  lane.stalled = stalled;

  // Time spent in the CURRENT phase (stage_since is stamped by state.sh on each
  // stage change). Informational — shown on the card + map; replaces the old
  // 3x-NO-GO retry cap as the "is this lane stuck?" signal.
  let stageAge = null;
  if (lane.stage_since) {
    const ts = new Date(lane.stage_since);
    if (!isNaN(ts.getTime())) stageAge = Math.round((Date.now() - ts.getTime()) / 1000);
  }
  lane.stage_age_sec = stageAge;

  return lane;
}

export async function lanesPayload() {
  const nums = discoverLanes();
  const lanes = await Promise.all(nums.map(n => readLane(n)));
  return { lanes, stall_sec: STALL_SEC, config: harnessConfig() };
}
