// Dashboard slug correlation: proofPayload() must join proof dirs to per-feature
// state BY SLUG, so switching features on the dashboard shows the right data.
// (config.js reads HARNESS_ROOT/LANES_ROOT at import time, so set env, then
// dynamic-import the module under test.)
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import fs from 'fs';
import os from 'os';
import path from 'path';

let tmp, proofPayload;

function writeProof(slug, group, file, lane = 3) {
  const d = path.join(process.env.LANES_ROOT, `lane${lane}`, '.playwright-mcp', 'proof', slug, group);
  fs.mkdirSync(d, { recursive: true });
  fs.writeFileSync(path.join(d, file), 'x');
}
function writeState(slug, obj, lane = 3) {
  const d = path.join(process.env.HARNESS_ROOT, 'state', `lane${lane}`);
  fs.mkdirSync(d, { recursive: true });
  fs.writeFileSync(path.join(d, `${slug}.json`), JSON.stringify(obj));
}
function writeActive(slug, lane) {
  const d = path.join(process.env.HARNESS_ROOT, 'state', `lane${lane}`);
  fs.mkdirSync(d, { recursive: true });
  fs.writeFileSync(path.join(d, '.active'), slug);
}
function writePending(obj, lane) {
  const d = path.join(process.env.HARNESS_ROOT, 'state', `lane${lane}`);
  fs.mkdirSync(d, { recursive: true });
  fs.writeFileSync(path.join(d, '_pending.json'), JSON.stringify(obj));
  fs.writeFileSync(path.join(d, '.active'), '');   // pre-activate: no active slug yet
}

beforeAll(async () => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'harness-proof-'));
  process.env.HARNESS_ROOT = path.join(tmp, 'harness');
  process.env.LANES_ROOT = path.join(tmp, 'lanes');

  // a fully-tracked feature: proof + matching state
  writeProof('csv-export', 'qc-local', '01-shot.png');
  writeProof('csv-export', 'qc-dev', '02-dev.png');
  writeState('csv-export', { stage: 'done', status: 'passed', feature_title: 'CSV export', pr_url: 'http://x/pull/7' });

  // an orphan: proof with NO matching state file (slugs differ)
  writeProof('orphan-feat', 'qc-dev', '01.png');

  // lane 4: an ACTIVE feature with state but NO proof dir yet (the current,
  // in-progress feature) + a past feature that does have proof.
  writeProof('old-done', 'qc-local', '01.png', 4);
  writeState('wip-active', { stage: 'implementing', status: 'running', feature_title: 'WIP active' }, 4);
  writeActive('wip-active', 4);

  // lane 5: a PRE-ACTIVATE _pending feature (title set, .active empty, no proof).
  writeProof('prev-feat', 'qc-dev', '01.png', 5);
  writePending({ stage: 'plan', feature_title: 'Planning a thing' }, 5);

  ({ proofPayload } = await import('../server/services/proof.js'));
});
afterAll(() => { try { fs.rmSync(tmp, { recursive: true, force: true }); } catch { /* ignore */ } });

describe('proofPayload slug correlation', () => {
  it('lists a feature by its slug with grouped screenshots', () => {
    const p = proofPayload(3);
    expect(p.lane).toBe(3);
    const feat = p.features.find(f => f.slug === 'csv-export');
    expect(feat).toBeTruthy();
    expect(feat.groups['qc-local']).toContain('01-shot.png');
    expect(feat.groups['qc-dev']).toContain('02-dev.png');
  });

  it('attaches per-feature state to the proof feature by matching slug', () => {
    const feat = proofPayload(3).features.find(f => f.slug === 'csv-export');
    expect(feat.state).toBeTruthy();
    expect(feat.state.feature_title).toBe('CSV export');
    expect(feat.state.stage).toBe('done');
    expect(feat.state.pr_url).toBe('http://x/pull/7');
  });

  it('leaves state undefined when the proof slug has no matching state file', () => {
    const feat = proofPayload(3).features.find(f => f.slug === 'orphan-feat');
    expect(feat).toBeTruthy();          // still listed (has proof)
    expect(feat.state).toBeUndefined(); // but no state correlated
  });
});

// The gallery must stay consistent with the lane card/header, which read STATE.
// So proofPayload must surface the CURRENT feature (from .active or _pending) even
// when it has no proof dir yet, and mark it so the client defaults to it.
describe('proofPayload surfaces the current feature from state', () => {
  it('lists an active feature that has state but no proof dir, pins it first, marks it current', () => {
    const p = proofPayload(4);
    expect(p.current).toBe('wip-active');
    const feat = p.features.find(f => f.slug === 'wip-active');
    expect(feat).toBeTruthy();                     // surfaced despite no proof dir
    expect(feat.state.feature_title).toBe('WIP active');
    expect(feat.groups).toEqual({});               // no screenshots yet
    expect(p.features[0].slug).toBe('wip-active');  // pinned first → default selection
    // the past feature with proof is still listed too
    expect(p.features.some(f => f.slug === 'old-done')).toBe(true);
  });

  it('surfaces a pre-activate _pending feature as the current one', () => {
    const p = proofPayload(5);
    expect(p.current).toBeTruthy();                // not '' — derived from _pending, not the branch
    const cur = p.features.find(f => f.slug === p.current);
    expect(cur).toBeTruthy();
    expect(cur.state.feature_title).toBe('Planning a thing');
    expect(cur.groups).toEqual({});
  });
});
