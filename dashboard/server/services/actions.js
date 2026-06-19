import { spawn, spawnSync } from 'child_process';
import fs from 'fs';
import path from 'path';
import { BIN, HARNESS_ROOT } from './config.js';
import { archiveFeatureState } from './proof.js';
import { applyCreds } from './creds.js';

function script(name) { return path.join(BIN, name); }

function ensureLogDir() {
  const logdir = path.join(HARNESS_ROOT, 'logs');
  fs.mkdirSync(logdir, { recursive: true });
  return logdir;
}

function spawnBg(cmd, env) {
  const logdir = ensureLogDir();
  const logPath = path.join(logdir, 'dashboard-actions.log');
  const logFd = fs.openSync(logPath, 'a');
  const ts = new Date().toISOString();
  fs.appendFileSync(logFd, `\n=== ${ts} :: ${cmd.join(' ')} ===\n`);
  const child = spawn(cmd[0], cmd.slice(1), {
    stdio: ['ignore', logFd, logFd],
    detached: true,
    env: env || undefined,
  });
  child.unref();
}

function runSync(cmds, env, timeout = 300000) {
  const logdir = ensureLogDir();
  const logPath = path.join(logdir, 'dashboard-actions.log');
  const chunks = [];

  for (const cmd of cmds) {
    const label = cmd[0] === 'bash' && cmd.length > 1 ? path.basename(cmd[1]) : cmd.join(' ');
    fs.appendFileSync(logPath, `\n=== ${new Date().toISOString()} :: ${label} ===\n`);

    const r = spawnSync(cmd[0], cmd.slice(1), {
      encoding: 'utf8',
      timeout,
      env: env || undefined,
    });

    if (r.error && r.error.code === 'ETIMEDOUT') {
      const msg = `$ ${label}\n[timed out after ${timeout / 1000}s]`;
      fs.appendFileSync(logPath, msg + '\n');
      chunks.push(msg);
      return { ok: false, output: chunks.join('\n') };
    }

    const out = ((r.stdout || '') + (r.stderr || '')).trim();
    fs.appendFileSync(logPath, out + '\n');
    chunks.push(out ? `$ ${label}\n${out}` : `$ ${label}\n(ok)`);

    if (r.status !== 0) {
      chunks.push(`[exit ${r.status}]`);
      return { ok: false, output: chunks.join('\n') };
    }
  }
  return { ok: true, output: chunks.join('\n') };
}

export function runAction(lane, action, params) {
  if (action === 'up') {
    spawnBg(['bash', script('lane-up.sh'), String(lane)]);
  } else if (action === 'down') {
    spawnSync('bash', [script('lane-down.sh'), String(lane)], { timeout: 60000 });
  } else if (action === 'clear') {
    archiveFeatureState(lane);
    spawnSync('bash', [script('state.sh'), String(lane), 'init'], { timeout: 15000 });
  } else if (action === 'reset') {
    spawnBg(['bash', script('lane-reset.sh'), String(lane)]);
  } else if (action === 'remove') {
    spawnBg(['bash', script('lane-remove.sh'), String(lane)]);
  } else if (action === 'add') {
    const email = ((params || {}).email || '').trim();
    const password = (params || {}).password || '';
    let env = null;
    if (email || password) {
      env = { ...process.env };
      if (email) env.LANE_DEV_QC_EMAIL = email;
      if (password) env.LANE_DEV_QC_PASSWORD = password;
    }
    spawnBg(['bash', script('lane-add.sh')], env);
  } else if (action === 'repopulate') {
    const { env, preCmds, notes } = applyCreds(lane, params || {});
    const res = runSync([...preCmds,
      ['bash', script('lane-agents-install.sh'), String(parseInt(lane, 10))],
      ['bash', script('lane-mcp-sync.sh'), String(parseInt(lane, 10))],
    ], env);
    if (notes.length) res.output = notes.join('\n') + '\n' + (res.output || '');
    return res;
  } else if (action === 'creds') {
    const { env, preCmds, notes } = applyCreds(lane, params || {});
    if (!preCmds.length && !notes.length) throw new Error('no credentials provided');
    const res = runSync([...preCmds,
      ['bash', script('lane-agents-install.sh'), String(parseInt(lane, 10))],
      ['bash', script('lane-qa-login.sh'), String(parseInt(lane, 10)), 'all'],
    ], env);
    if (notes.length) res.output = notes.join('\n') + '\n' + (res.output || '');
    return res;
  } else {
    throw new Error(`unknown action ${action}`);
  }
  return null;
}
