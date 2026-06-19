import fs from 'fs';
import path from 'path';
import { LANES_ROOT, SECRETS_ENV, BIN } from './config.js';

function parseEnv(filePath) {
  const out = {};
  if (!fs.existsSync(filePath)) return out;
  for (const line of fs.readFileSync(filePath, 'utf8').split('\n')) {
    const m = line.match(/^\s*export\s+(\w+)=(.*)$/);
    if (!m) continue;
    let v = m[2].trim();
    if (v.length >= 2 && (v[0] === '"' || v[0] === "'") && v[v.length - 1] === v[0])
      v = v.slice(1, -1);
    out[m[1]] = v;
  }
  return out;
}

export function credsCurrent(n) {
  const laneEnv = parseEnv(path.join(LANES_ROOT, `lane${n}`, '.harness-qa.env'));
  const sec = parseEnv(SECRETS_ENV);
  return {
    lane: n,
    dev: { email: laneEnv.DEV_QC_EMAIL || '', password: laneEnv.DEV_QC_PASSWORD || '' },
    local: { email: sec.SEED_USER_EMAIL || '', password: sec.SEED_USER_PASSWORD || '' },
    tracker: { email: sec.TRACKER_EMAIL || '', password: sec.TRACKER_PASSWORD || '' },
  };
}

function setSecrets(pairs) {
  const fmt = (k, v) => `export ${k}='${String(v).replace(/'/g, "'\\''")}'`;
  let lines = [];
  if (fs.existsSync(SECRETS_ENV)) lines = fs.readFileSync(SECRETS_ENV, 'utf8').split('\n');
  // remove trailing empty line from split
  if (lines.length && lines[lines.length - 1] === '') lines.pop();

  const seen = new Set();
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(/^\s*export\s+(\w+)=/);
    if (m && m[1] in pairs) {
      lines[i] = fmt(m[1], pairs[m[1]]);
      seen.add(m[1]);
    }
  }
  for (const [k, v] of Object.entries(pairs)) {
    if (!seen.has(k)) lines.push(fmt(k, v));
  }
  fs.writeFileSync(SECRETS_ENV, lines.join('\n') + '\n');
}

export function applyCreds(lane, creds) {
  const env = { ...process.env };
  const preCmds = [];
  const notes = [];

  const dev = (creds || {}).dev || {};
  if (dev.email || dev.password) {
    if (dev.email) env.LANE_DEV_QC_EMAIL = dev.email;
    if (dev.password) env.LANE_DEV_QC_PASSWORD = dev.password;
    preCmds.push(['bash', path.join(BIN, 'lane-qa-creds.sh'), String(parseInt(lane, 10)), '--force']);
  }

  const sec = {};
  const loc = (creds || {}).local || {};
  const trk = (creds || {}).tracker || {};
  if (loc.email) sec.SEED_USER_EMAIL = loc.email;
  if (loc.password) sec.SEED_USER_PASSWORD = loc.password;
  if (trk.email) sec.TRACKER_EMAIL = trk.email;
  if (trk.password) sec.TRACKER_PASSWORD = trk.password;

  if (Object.keys(sec).length) {
    setSecrets(sec);
    notes.push('updated shared secrets.env: ' + Object.keys(sec).sort().join(', '));
  }

  return { env, preCmds, notes };
}
