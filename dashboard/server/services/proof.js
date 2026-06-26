import fs from 'fs';
import path from 'path';
import { LANES_ROOT, STATE_DIR } from './config.js';

function proofBase(n) {
  return path.join(LANES_ROOT, `lane${n}`, '.playwright-mcp', 'proof');
}

export function archiveFeatureState(n) {
  const stateDir = path.join(STATE_DIR, `lane${n}`);
  const flatFile = path.join(STATE_DIR, `lane${n}.json`);

  // Per-feature directory format: stamp _archived_at on the active feature's file
  if (fs.existsSync(stateDir) && fs.statSync(stateDir).isDirectory()) {
    try {
      let active = '';
      try { active = fs.readFileSync(path.join(stateDir, '.active'), 'utf8').trim(); } catch { /* ok */ }
      const target = active ? path.join(stateDir, `${active}.json`) : path.join(stateDir, '_pending.json');
      if (fs.existsSync(target)) {
        const state = JSON.parse(fs.readFileSync(target, 'utf8'));
        state._archived_at = new Date().toISOString();
        fs.writeFileSync(target, JSON.stringify(state, null, 2));
      }
    } catch { /* best effort */ }
    return;
  }

  // Legacy flat-file fallback: archive to lane-history dir
  if (!fs.existsSync(flatFile)) return;
  try {
    const state = JSON.parse(fs.readFileSync(flatFile, 'utf8'));
    if (!state.feature_title && !state.branch) return;
    const branch = state.branch || '';
    const slug = branch.replace(/^feat\//, '').replace(/\//g, '-') || 'no-branch';
    const historyDir = path.join(STATE_DIR, `lane${n}-history`);
    fs.mkdirSync(historyDir, { recursive: true });
    const ts = new Date().toISOString().replace(/[-:]/g, '').replace(/T/, '-').slice(0, 15);
    state._archived_at = new Date().toISOString();
    fs.writeFileSync(path.join(historyDir, `${ts}-${slug}.json`), JSON.stringify(state, null, 2));
  } catch { /* best effort */ }
}

export function proofPayload(n) {
  const base = proofBase(n);
  const feats = [];

  if (fs.existsSync(base) && fs.statSync(base).isDirectory()) {
    for (const slug of fs.readdirSync(base).sort()) {
      const d = path.join(base, slug);
      try { if (!fs.statSync(d).isDirectory()) continue; } catch { continue; }

      const groups = {};
      for (const grp of fs.readdirSync(d).sort()) {
        const g = path.join(d, grp);
        try { if (!fs.statSync(g).isDirectory() || grp === 'ticket') continue; } catch { continue; }
        const imgs = fs.readdirSync(g)
          .filter(f => /\.(png|jpg|jpeg)$/i.test(f))
          .sort();
        if (imgs.length) groups[grp] = imgs;
      }

      let ticketRel = '';
      if (fs.existsSync(path.join(d, 'ticket', 'REPORT.html')))
        ticketRel = `${slug}/ticket/REPORT.html`;

      if (Object.keys(groups).length || ticketRel) {
        let mt = 0;
        try {
          const walk = (dir) => {
            for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
              const full = path.join(dir, e.name);
              if (e.isDirectory()) walk(full);
              else { const s = fs.statSync(full); if (s.mtimeMs > mt) mt = s.mtimeMs; }
            }
          };
          walk(d);
        } catch { /* best effort */ }
        feats.push({ slug, groups, ticket_report: ticketRel, mtime: mt / 1000 });
      }
    }
  }

  feats.sort((a, b) => (b.mtime || 0) - (a.mtime || 0));

  const pickState = (st) => {
    const o = {};
    for (const k of ['stage', 'status', 'pr_url', 'gate_decision', 'feature_title', 'ticket_url', 'notes', '_archived_at'])
      o[k] = st[k] || '';
    return o;
  };

  // Enrich features with per-feature state from state/laneN/, AND surface the CURRENT
  // feature — the active slug, or the pre-activate _pending feature — even when it has
  // no proof dir yet. The gallery must read the SAME source of truth as the lane card/
  // header (state); otherwise a just-started feature (no screenshots, branch still on
  // main) is invisible here and the gallery falls back to a stale older feature.
  const stateDir = path.join(STATE_DIR, `lane${n}`);
  const archived = {};
  let curSlug = '';
  let pendingState = null;

  if (fs.existsSync(stateDir) && fs.statSync(stateDir).isDirectory()) {
    for (const fname of fs.readdirSync(stateDir)) {
      if (!fname.endsWith('.json') || fname === '_pending.json') continue;
      const slug = fname.replace(/\.json$/, '');
      try { archived[slug] = pickState(JSON.parse(fs.readFileSync(path.join(stateDir, fname), 'utf8'))); }
      catch { /* skip bad files */ }
    }
    // current feature: the active slug, else the pre-activate _pending feature
    try { curSlug = fs.readFileSync(path.join(stateDir, '.active'), 'utf8').trim(); } catch { /* none */ }
    if (!curSlug) {
      try {
        const pj = JSON.parse(fs.readFileSync(path.join(stateDir, '_pending.json'), 'utf8'));
        if (pj.feature_title) { curSlug = '_active'; pendingState = pickState(pj); }
      } catch { /* no pending feature */ }
    }
  } else {
    // Legacy fallback: read from lane-history dir
    const historyDir = path.join(STATE_DIR, `lane${n}-history`);
    if (fs.existsSync(historyDir)) {
      for (const fname of fs.readdirSync(historyDir).sort().reverse()) {
        if (!fname.endsWith('.json')) continue;
        try {
          const st = JSON.parse(fs.readFileSync(path.join(historyDir, fname), 'utf8'));
          const s = (st.branch || '').replace(/^feat\//, '').replace(/\//g, '-');
          if (s && !(s in archived)) archived[s] = pickState(st);
        } catch { /* skip bad files */ }
      }
    }
  }

  // attach state to the proof-backed features
  for (const feat of feats) {
    if (feat.slug in archived) feat.state = archived[feat.slug];
  }

  // surface features that have STATE but no proof dir yet (incl. the current one)
  const have = new Set(feats.map(f => f.slug));
  for (const slug of Object.keys(archived)) {
    if (!have.has(slug)) { feats.push({ slug, groups: {}, ticket_report: '', mtime: 0, state: archived[slug] }); have.add(slug); }
  }
  if (pendingState && !have.has('_active'))
    feats.push({ slug: '_active', groups: {}, ticket_report: '', mtime: 0, state: pendingState });

  // pin the current feature first so the client defaults to it
  if (curSlug) {
    const i = feats.findIndex(f => f.slug === curSlug);
    if (i > 0) { const [c] = feats.splice(i, 1); feats.unshift(c); }
  }

  return { lane: n, features: feats, current: curSlug };
}

export function proofFile(n, relpath) {
  let base;
  try {
    base = fs.realpathSync(proofBase(n));
  } catch {
    return null;
  }
  let p;
  try {
    p = fs.realpathSync(path.join(base, relpath));
  } catch {
    return null;
  }
  if (p.startsWith(base + path.sep) && fs.existsSync(p) && fs.statSync(p).isFile()
      && /\.(png|jpg|jpeg|html)$/i.test(p)) {
    return p;
  }
  return null;
}

function countFiles(dir) {
  let c = 0;
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.isDirectory()) c += countFiles(path.join(dir, e.name));
    else c++;
  }
  return c;
}

const badName = (s) =>
  !s || typeof s !== 'string' || s.includes('/') || s.includes('\\') || s.includes('..');

// Delete proof SCREENSHOTS for lane n at one of three granularities:
//   { slug, group, images:[...] } -> unlink those files (then prune empty group)
//   { slug, group }               -> remove the whole group dir
//   { slug }                      -> remove every image group dir (keeps ticket/)
// Never touches the `ticket` group, state JSON, or anything outside proofBase(n).
export function deleteProof(n, { slug, group, images } = {}) {
  if (badName(slug)) throw new Error('invalid slug');

  let base;
  try { base = fs.realpathSync(proofBase(n)); }
  catch { throw new Error('no proof for this lane'); }
  const inBase = (p) => p === base || p.startsWith(base + path.sep);

  let featDir;
  try { featDir = fs.realpathSync(path.join(base, slug)); }
  catch { throw new Error('feature not found'); }
  if (!inBase(featDir) || !fs.statSync(featDir).isDirectory())
    throw new Error('invalid feature dir');

  let deleted = 0;

  if (group !== undefined) {
    if (badName(group) || group === 'ticket') throw new Error('invalid group');
    let grpDir;
    try { grpDir = fs.realpathSync(path.join(featDir, group)); }
    catch { throw new Error('group not found'); }
    if (!inBase(grpDir) || !fs.statSync(grpDir).isDirectory())
      throw new Error('invalid group dir');

    if (Array.isArray(images) && images.length) {
      for (const img of images) {
        if (badName(img) || !/\.(png|jpg|jpeg)$/i.test(img)) throw new Error('invalid image');
        let f;
        try { f = fs.realpathSync(path.join(grpDir, img)); } catch { continue; }
        if (inBase(f) && fs.statSync(f).isFile() && /\.(png|jpg|jpeg)$/i.test(f)) {
          fs.unlinkSync(f); deleted++;
        }
      }
      try { if (!fs.readdirSync(grpDir).length) fs.rmdirSync(grpDir); } catch { /* ok */ }
    } else {
      deleted = countFiles(grpDir);
      fs.rmSync(grpDir, { recursive: true, force: true });
    }
  } else {
    for (const e of fs.readdirSync(featDir, { withFileTypes: true })) {
      if (!e.isDirectory() || e.name === 'ticket') continue;
      const g = path.join(featDir, e.name);
      deleted += countFiles(g);
      fs.rmSync(g, { recursive: true, force: true });
    }
  }

  return { ok: true, deleted };
}
