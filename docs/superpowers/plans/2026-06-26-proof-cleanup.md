# Proof Screenshot Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a dashboard feature that lets the user clean up (permanently delete) a lane feature's QC proof screenshots at three granularities — individual shots, a whole group, or all of a feature's screenshots.

**Architecture:** One `DELETE /api/proof/:n` endpoint backed by a `deleteProof()` service that reuses the existing realpath-containment guard from `proofFile`. The gallery gets a "🧹 clean up" toggle (Option A) that reveals per-shot checkboxes, per-group trash buttons, and a clear-all button; all deletes route through an extended `ConfirmModal` and force-refresh proof afterward. Screenshots only — state records and ticket reports are never touched.

**Tech Stack:** Node.js + Express (server), React 18 + Vite (frontend), Vitest (tests). All under `dashboard/`.

---

## File Structure

- `dashboard/server/services/proof.js` — add `deleteProof(n, {slug, group, images})` + a `countFiles` helper (modify).
- `dashboard/server/routes/proof.js` — add `DELETE /api/proof/:n` route (modify).
- `dashboard/test/delete-proof.test.js` — new unit tests for `deleteProof` (create).
- `dashboard/src/lib/api.js` — add `deleteProof(n, body)` client (modify).
- `dashboard/src/components/ConfirmModal.jsx` — accept optional generic `{title, message, confirmLabel, confirmCls}` (modify).
- `dashboard/src/components/ProofGallery.jsx` — cleanup mode UI (modify).
- `dashboard/src/App.jsx` — wire `onCleanup` handler + extended ConfirmModal props (modify).
- `dashboard/src/index.css` — styles for cleanup controls (modify).

---

## Task 1: `deleteProof` service (backend, TDD)

**Files:**
- Modify: `dashboard/server/services/proof.js`
- Test: `dashboard/test/delete-proof.test.js` (create)

- [ ] **Step 1: Write the failing tests**

Create `dashboard/test/delete-proof.test.js`:

```js
// deleteProof() must remove screenshots at three granularities (files / group /
// whole feature), enforce realpath containment (no traversal), refuse the ticket
// group, prune empty group dirs, and never touch state JSON.
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import fs from 'fs';
import os from 'os';
import path from 'path';

let tmp, deleteProof;

function proofDir(slug, group, lane = 3) {
  return path.join(process.env.LANES_ROOT, `lane${lane}`, '.playwright-mcp', 'proof', slug, group);
}
function writeProof(slug, group, file, lane = 3) {
  const d = proofDir(slug, group, lane);
  fs.mkdirSync(d, { recursive: true });
  fs.writeFileSync(path.join(d, file), 'x');
}
function writeState(slug, obj, lane = 3) {
  const d = path.join(process.env.HARNESS_ROOT, 'state', `lane${lane}`);
  fs.mkdirSync(d, { recursive: true });
  fs.writeFileSync(path.join(d, `${slug}.json`), JSON.stringify(obj));
}

beforeEach(async () => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'harness-del-'));
  process.env.HARNESS_ROOT = path.join(tmp, 'harness');
  process.env.LANES_ROOT = path.join(tmp, 'lanes');

  writeProof('csv-export', 'qc-local', '01-shot.png');
  writeProof('csv-export', 'qc-local', '02-shot.png');
  writeProof('csv-export', 'qc-dev', '01-dev.png');
  // a ticket report dir (must never be deleted)
  const tdir = proofDir('csv-export', 'ticket');
  fs.mkdirSync(tdir, { recursive: true });
  fs.writeFileSync(path.join(tdir, 'REPORT.html'), '<html>');
  // a state record (must never be deleted)
  writeState('csv-export', { stage: 'done', feature_title: 'CSV export' });

  ({ deleteProof } = await import('../server/services/proof.js'));
});
afterEach(() => { try { fs.rmSync(tmp, { recursive: true, force: true }); } catch { /* ignore */ } });

describe('deleteProof', () => {
  it('deletes named image files within a group and returns the count', () => {
    const r = deleteProof(3, { slug: 'csv-export', group: 'qc-local', images: ['01-shot.png'] });
    expect(r).toEqual({ ok: true, deleted: 1 });
    expect(fs.existsSync(path.join(proofDir('csv-export', 'qc-local'), '01-shot.png'))).toBe(false);
    expect(fs.existsSync(path.join(proofDir('csv-export', 'qc-local'), '02-shot.png'))).toBe(true);
  });

  it('prunes a group dir that becomes empty after deleting its last file', () => {
    deleteProof(3, { slug: 'csv-export', group: 'qc-dev', images: ['01-dev.png'] });
    expect(fs.existsSync(proofDir('csv-export', 'qc-dev'))).toBe(false);
  });

  it('deletes a whole group dir', () => {
    const r = deleteProof(3, { slug: 'csv-export', group: 'qc-local' });
    expect(r.deleted).toBe(2);
    expect(fs.existsSync(proofDir('csv-export', 'qc-local'))).toBe(false);
    expect(fs.existsSync(proofDir('csv-export', 'qc-dev'))).toBe(true);
  });

  it('clears all image groups for a feature but keeps ticket and state', () => {
    const r = deleteProof(3, { slug: 'csv-export' });
    expect(r.deleted).toBe(3);
    expect(fs.existsSync(proofDir('csv-export', 'qc-local'))).toBe(false);
    expect(fs.existsSync(proofDir('csv-export', 'qc-dev'))).toBe(false);
    // ticket report + state untouched
    expect(fs.existsSync(path.join(proofDir('csv-export', 'ticket'), 'REPORT.html'))).toBe(true);
    expect(fs.existsSync(path.join(process.env.HARNESS_ROOT, 'state', 'lane3', 'csv-export.json'))).toBe(true);
  });

  it('refuses to delete the ticket group', () => {
    expect(() => deleteProof(3, { slug: 'csv-export', group: 'ticket' })).toThrow();
    expect(fs.existsSync(path.join(proofDir('csv-export', 'ticket'), 'REPORT.html'))).toBe(true);
  });

  it('rejects path traversal in slug, group, and image names', () => {
    expect(() => deleteProof(3, { slug: '../../etc' })).toThrow();
    expect(() => deleteProof(3, { slug: 'csv-export', group: '../qc-dev' })).toThrow();
    expect(() => deleteProof(3, { slug: 'csv-export', group: 'qc-local', images: ['../01-dev.png'] })).toThrow();
  });

  it('throws when the proof base or feature dir does not exist', () => {
    expect(() => deleteProof(9, { slug: 'csv-export' })).toThrow();
    expect(() => deleteProof(3, { slug: 'no-such-feature' })).toThrow();
  });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd dashboard && npx vitest run test/delete-proof.test.js`
Expected: FAIL — `deleteProof is not a function` (export missing).

- [ ] **Step 3: Implement `deleteProof` + `countFiles`**

In `dashboard/server/services/proof.js`, add at the end of the file (after `proofFile`):

```js
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd dashboard && npx vitest run test/delete-proof.test.js`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add dashboard/server/services/proof.js dashboard/test/delete-proof.test.js
git commit -m "feat(dashboard): deleteProof service with realpath-guarded screenshot cleanup"
```

---

## Task 2: `DELETE /api/proof/:n` route (backend)

**Files:**
- Modify: `dashboard/server/routes/proof.js`

- [ ] **Step 1: Import `deleteProof` and add the route**

In `dashboard/server/routes/proof.js`, change the import line:

```js
import { proofPayload, proofFile, deleteProof } from '../services/proof.js';
```

Then add this route immediately after the `/api/reviews/:n` route (before the `/proof/:n/*` static route):

```js
router.delete('/api/proof/:n(\\d)', (req, res) => {
  try {
    res.json(deleteProof(parseInt(req.params.n, 10), req.body || {}));
  } catch (e) {
    res.status(400).json({ ok: false, error: e.message });
  }
});
```

- [ ] **Step 2: Verify the server starts without errors**

Run: `cd dashboard && node -e "import('./server/routes/proof.js').then(()=>console.log('route module OK'))"`
Expected: prints `route module OK` (no import/syntax error).

- [ ] **Step 3: Smoke-test the endpoint end to end**

Run:
```bash
cd dashboard && node -e '
import("./server/services/proof.js");
import("express").then(async ({default: express}) => {
  const app = express(); app.use(express.json());
  const r = (await import("./server/routes/proof.js")).default;
  app.use(r);
  const srv = app.listen(0, async () => {
    const port = srv.address().port;
    const res = await fetch(`http://127.0.0.1:${port}/api/proof/3`, { method: "DELETE", headers: {"Content-Type":"application/json"}, body: JSON.stringify({}) });
    console.log("status", res.status, await res.text());
    srv.close();
  });
});'
```
Expected: `status 400 {"ok":false,"error":"invalid slug"}` — confirms the route is wired and validation runs.

- [ ] **Step 4: Commit**

```bash
git add dashboard/server/routes/proof.js
git commit -m "feat(dashboard): DELETE /api/proof/:n route"
```

---

## Task 3: API client `deleteProof`

**Files:**
- Modify: `dashboard/src/lib/api.js`

- [ ] **Step 1: Add the client function**

Append to `dashboard/src/lib/api.js`:

```js
export async function deleteProof(n, body) {
  return checked(await fetch(`/api/proof/${n}`, {
    method: 'DELETE',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body || {}),
  }));
}
```

- [ ] **Step 2: Verify the build still compiles**

Run: `cd dashboard && npm run build`
Expected: build succeeds (no errors).

- [ ] **Step 3: Commit**

```bash
git add dashboard/src/lib/api.js
git commit -m "feat(dashboard): deleteProof api client"
```

---

## Task 4: Extend `ConfirmModal` for generic messages

**Files:**
- Modify: `dashboard/src/components/ConfirmModal.jsx`

- [ ] **Step 1: Replace the component with the extended version**

Replace the entire contents of `dashboard/src/components/ConfirmModal.jsx` with:

```jsx
import React from 'react';
import Modal from './Modal.jsx';
import { ACT_CONFIRM } from '../lib/constants.js';

// Backwards compatible: when `action` is given it looks up copy from ACT_CONFIRM.
// Callers may instead pass generic { title, message, confirmLabel, confirmCls }
// to override that copy (used by the proof-cleanup flows).
export default function ConfirmModal({
  lane, action, title, message, confirmLabel, confirmCls, onConfirm, onClose,
}) {
  if (!action && !message) return null;
  const c = ACT_CONFIRM[action] || { m: 'Proceed?', y: 'OK' };
  const yLabel = confirmLabel || c.y || 'Confirm';
  const ttl = title || `Lane ${lane}: ${yLabel.toLowerCase()}?`;
  const msg = message || c.m;
  const yCls = confirmCls || c.cls || '';
  return (
    <Modal title={ttl} onClose={onClose}
      buttons={[
        { label: 'Cancel', fn: onClose },
        { label: yLabel, cls: yCls, fn: () => { onClose(); onConfirm(); } },
      ]}>
      <p className="m-text">{msg}</p>
    </Modal>
  );
}
```

- [ ] **Step 2: Verify the build still compiles**

Run: `cd dashboard && npm run build`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add dashboard/src/components/ConfirmModal.jsx
git commit -m "feat(dashboard): ConfirmModal accepts generic message/title props"
```

---

## Task 5: Cleanup mode in `ProofGallery` + App wiring + CSS

**Files:**
- Modify: `dashboard/src/components/ProofGallery.jsx`
- Modify: `dashboard/src/App.jsx`
- Modify: `dashboard/src/index.css`

- [ ] **Step 1: Replace `ProofGallery.jsx` with the cleanup-mode version**

Replace the entire contents of `dashboard/src/components/ProofGallery.jsx` with:

```jsx
import React from 'react';
import { fmtWhen, prNum } from '../lib/format.js';

function imgUrl(n, slug, grp, img) {
  return `/proof/${n}/${encodeURIComponent(slug)}/${encodeURIComponent(grp)}/${encodeURIComponent(img)}`;
}

function handleImgError(e) {
  e.target.onerror = null;
  e.target.style.opacity = '.12';
  e.target.style.background = '#1a2029';
}

export default function ProofGallery({ proof, selectedLane, selectedSlug, onSelectFeature, onShot, onGallery, onCleanup }) {
  const [cleanup, setCleanup] = React.useState(false);
  const [selected, setSelected] = React.useState(() => new Set());

  // reset selection when feature changes or cleanup mode turns off
  React.useEffect(() => { setSelected(new Set()); }, [selectedSlug]);
  React.useEffect(() => { if (!cleanup) setSelected(new Set()); }, [cleanup]);

  const toggleSel = (key) => setSelected(prev => {
    const next = new Set(prev);
    if (next.has(key)) next.delete(key); else next.add(key);
    return next;
  });

  if (!proof) return <span className="pf-empty">loading proof…</span>;
  const n = selectedLane;
  const sel = selectedSlug;
  const d = proof;

  const featBySlug = new Map((d.features || []).map(x => [x.slug, x]));
  const labelOf = (slug) => {
    const t = featBySlug.get(slug)?.state?.feature_title;
    if (slug === '_active' && t) return t.length > 44 ? t.slice(0, 43) + '…' : t;
    return slug;
  };
  const opts = [];
  const seen = new Set();
  if (d._cur) { opts.push([d._cur, labelOf(d._cur) + ' • current']); seen.add(d._cur); }
  (d.features || []).forEach(f => {
    if (!seen.has(f.slug)) {
      opts.push([f.slug, labelOf(f.slug) + (f.slug === d._cur ? ' • current' : '')]);
      seen.add(f.slug);
    }
  });

  const f = (d.features || []).find(x => x.slug === sel);
  const hasShots = !!(f && Object.keys(f.groups || {}).length);

  const picker = opts.length > 1 ? (
    <select className="pf-sel" value={sel} onChange={e => onSelectFeature(n, e.target.value)}
      title="choose which feature's proof to view">
      {opts.map(([v, t]) => <option key={v} value={v}>{t}</option>)}
    </select>
  ) : null;

  const head = (
    <>
      <span className="pf-slug">{'\u{1F4F8}'} {sel ? labelOf(sel) : '(current feature)'}</span>
      {sel === d._cur
        ? <span className="pf-cur">current</span>
        : <span className="pf-prev">past</span>}
      {picker}
      {f && f.ticket_report && (
        <a className="pf-ticket" href={`/proof/${n}/${encodeURI(f.ticket_report)}`}
          target="_blank" rel="noreferrer" title="ticketer task report">
          {'\u{1F3AB}'} task report {'↗'}
        </a>
      )}
      {hasShots && (
        <button className={`pf-clean${cleanup ? ' on' : ''}`} onClick={() => setCleanup(c => !c)}
          title="toggle screenshot cleanup mode">
          {cleanup ? '✓ done' : '🧹 clean up'}
        </button>
      )}
      {hasShots && cleanup && (
        <button className="pf-clear-all warn"
          onClick={() => onCleanup(n, { slug: f.slug }, `all screenshots for "${labelOf(f.slug)}"`)}
          title="delete every screenshot for this feature">
          clear all screenshots
        </button>
      )}
    </>
  );

  let stateBar = null;
  if (f && f.state && sel !== d._cur) {
    const st = f.state;
    const gd = (st.gate_decision || '').toUpperCase();
    const gc = gd === 'GO' ? 'gate-go' : gd === 'NO-GO' ? 'gate-nogo' : '';
    stateBar = (
      <div className="pf-state">
        <span className="pf-state-chip">stage: {st.stage || '—'}</span>
        <span className="pf-state-chip">status: {st.status || '—'}</span>
        <span className={`pf-state-chip gchip ${gc}`}>{gd || '—'}</span>
        {st.pr_url
          ? <a href={st.pr_url} target="_blank" rel="noreferrer" style={{ fontSize: '10.5px' }}>PR {prNum(st.pr_url)} {'↗'}</a>
          : <span className="pf-state-chip">PR —</span>}
        {st.ticket_url && <a href={st.ticket_url} target="_blank" rel="noreferrer" style={{ fontSize: '10.5px' }}>{'\u{1F3AB}'} ticket {'↗'}</a>}
        {st._archived_at && <span className="pf-state-chip" style={{ color: 'var(--faint)' }}>cleared {fmtWhen(st._archived_at)}</span>}
      </div>
    );
  }

  if (!hasShots) {
    return (
      <div className="proof">
        <div className="pf-feat">{head}{stateBar}</div>
        <span className="pf-empty">{'\u{1F4F8}'} no QC proof captured yet for this feature</span>
      </div>
    );
  }

  const deleteSelected = () => {
    const byGroup = {};
    for (const k of selected) {
      const i = k.indexOf('/');
      const g = k.slice(0, i), img = k.slice(i + 1);
      (byGroup[g] ||= []).push(img);
    }
    onCleanup(n, { slug: f.slug, _multi: byGroup }, `${selected.size} selected screenshot${selected.size > 1 ? 's' : ''}`,
      () => setSelected(new Set()));
  };

  const CAP = 8;
  return (
    <div className="proof">
      <div className="pf-feat">
        {head}
        {stateBar}
        {Object.entries(f.groups).map(([g, imgs]) => {
          const vis = cleanup ? imgs : (imgs.length > CAP ? imgs.slice(0, CAP - 1) : imgs);
          return (
            <div className="pf-grp" key={g}>
              <span className="pf-g">{g} · {imgs.length}
                {cleanup && (
                  <button className="pf-del-grp" title={`delete the whole ${g} group`}
                    onClick={() => onCleanup(n, { slug: f.slug, group: g }, `the entire "${g}" group (${imgs.length} screenshot${imgs.length > 1 ? 's' : ''})`)}>
                    🗑
                  </button>
                )}
              </span>
              <div className="pf-thumbs">
                {vis.map((img) => {
                  const key = `${g}/${img}`;
                  const isSel = cleanup && selected.has(key);
                  return (
                    <a key={img} href={imgUrl(n, f.slug, g, img)}
                      className={isSel ? 'sel' : ''}
                      onClick={e => {
                        e.preventDefault();
                        if (cleanup) toggleSel(key); else onShot(f.slug, g, imgs.indexOf(img));
                      }}
                      title={cleanup ? `${img} — click to select` : `${img} — click to preview`}>
                      <img loading="lazy" src={imgUrl(n, f.slug, g, img)} onError={handleImgError} />
                      {cleanup && <span className="pf-check">{isSel ? '☑' : '☐'}</span>}
                    </a>
                  );
                })}
                {!cleanup && imgs.length > CAP && (
                  <a className="pf-more" onClick={() => onGallery(f.slug, g)}
                    title={`show all ${imgs.length} screenshots`}>
                    +{imgs.length - (CAP - 1)}
                  </a>
                )}
              </div>
            </div>
          );
        })}
      </div>
      {cleanup && selected.size > 0 && (
        <div className="pf-bar">
          <span>{selected.size} selected</span>
          <button className="warn" onClick={deleteSelected}>delete {selected.size} selected</button>
          <button onClick={() => setSelected(new Set())}>clear selection</button>
        </div>
      )}
    </div>
  );
}
```

- [ ] **Step 2: Wire `onCleanup` in `App.jsx`**

In `dashboard/src/App.jsx`, change the api import line:

```jsx
import { postAction, deleteProof } from './lib/api.js';
```

Add this handler right after the existing `handleAction` `useCallback` block:

```jsx
  const handleCleanup = useCallback((n, payload, label, after) => {
    setConfirm({
      lane: n,
      title: 'Delete screenshots?',
      message: `Permanently delete ${label}? This cannot be undone.`,
      confirmLabel: 'Delete',
      confirmCls: 'warn',
      onConfirm: async () => {
        try {
          if (payload._multi) {
            for (const [group, images] of Object.entries(payload._multi))
              await deleteProof(n, { slug: payload.slug, group, images });
          } else {
            await deleteProof(n, payload);
          }
        } catch { /* gallery refresh below reflects truth */ }
        if (after) after();
        loadProof(n, true);
      },
    });
  }, [loadProof]);
```

Pass `onCleanup` to the gallery — change the `<ProofGallery .../>` usage to include it:

```jsx
              <ProofGallery proof={proof} selectedLane={selectedLane} selectedSlug={selectedSlug}
                onSelectFeature={selectFeature} onShot={openShot} onGallery={openGallery}
                onCleanup={handleCleanup} />
```

Pass the new generic props through to `ConfirmModal` — replace the `{confirm && (...)}` block with:

```jsx
      {confirm && (
        <ConfirmModal lane={confirm.lane} action={confirm.action}
          title={confirm.title} message={confirm.message}
          confirmLabel={confirm.confirmLabel} confirmCls={confirm.confirmCls}
          onConfirm={confirm.onConfirm} onClose={() => setConfirm(null)} />
      )}
```

- [ ] **Step 3: Add CSS for the cleanup controls**

Append to `dashboard/src/index.css`:

```css
/* proof cleanup mode */
.pf-clean { font-size: 10px; padding: 1px 8px; margin-right: 8px; border-radius: 8px; cursor: pointer;
  background: #161b24; color: var(--dim); border: 1px solid var(--line2) }
.pf-clean:hover { color: #cdd6e1; border-color: var(--blue) }
.pf-clean.on { background: rgba(96,165,250,.16); color: #cfe3ff; border-color: var(--blue) }
.pf-clear-all { font-size: 10px; padding: 1px 8px; border-radius: 8px; cursor: pointer }
.pf-del-grp { font-size: 10px; margin-left: 6px; padding: 0 5px; border-radius: 6px; cursor: pointer;
  background: transparent; border: 1px solid transparent; line-height: 1 }
.pf-del-grp:hover { background: rgba(248,113,113,.12); border-color: rgba(248,113,113,.4) }
.pf-thumbs a { position: relative }
.pf-thumbs a.sel img { border-color: var(--blue); outline: 2px solid var(--blue); opacity: 1 }
.pf-check { position: absolute; top: 2px; left: 2px; font-size: 13px; line-height: 1;
  color: #fff; text-shadow: 0 0 3px #000, 0 0 3px #000; pointer-events: none }
.pf-bar { display: flex; align-items: center; gap: 10px; margin-top: 8px; padding: 6px 10px;
  background: #161b24; border: 1px solid var(--line2); border-radius: 8px; font-size: 11px; color: #cdd6e1 }
.pf-bar button { font-size: 10.5px; padding: 2px 10px; border-radius: 6px; cursor: pointer }
```

- [ ] **Step 4: Verify the build compiles**

Run: `cd dashboard && npm run build`
Expected: build succeeds (no errors).

- [ ] **Step 5: Commit**

```bash
git add dashboard/src/components/ProofGallery.jsx dashboard/src/App.jsx dashboard/src/index.css
git commit -m "feat(dashboard): proof gallery cleanup mode (select/group/clear-all)"
```

---

## Task 6: Full verification

**Files:** none (verification only)

- [ ] **Step 1: Run the full test suite**

Run: `cd dashboard && npm test`
Expected: PASS — all existing `proof.test.js` tests plus the new `delete-proof.test.js` tests are green.

- [ ] **Step 2: Manual smoke in the running dashboard**

Run: `bin/dashboard.sh 8090` (or `bin/dashboard.sh restart 8090`), open `http://127.0.0.1:8090`, select a lane that has proof screenshots, and verify:
- the gallery looks unchanged by default;
- clicking **🧹 clean up** reveals checkboxes, per-group 🗑, and **clear all screenshots**;
- selecting shots shows the **delete N selected** bar; confirming deletes only those files and the gallery refreshes;
- deleting a group removes that group; **clear all screenshots** empties the feature but the task-report link (if any) still works;
- toggling **✓ done** returns to the normal read-only view.

Expected: all behaviors as described; state/ticket links remain intact.

- [ ] **Step 3: Confirm no stray changes**

Run: `git status`
Expected: working tree clean (everything committed across Tasks 1–5).
```
```

---

## Self-Review notes

- **Spec coverage:** three granularities → Task 1 (`images`/`group`/`slug` branches) + Task 5 UI (per-shot select / per-group 🗑 / clear-all); confirm+permanent → Task 4 + `handleCleanup`; realpath guard + ticket protection + state untouched → Task 1 tests; cleanup-mode toggle (Option A) → Task 5; server unit tests → Task 1; manual check → Task 6. No gaps.
- **Type consistency:** `deleteProof(n, {slug, group, images})` signature is identical in service, route, api client, and `handleCleanup`. `onCleanup(n, payload, label, after)` matches between `App.jsx` and `ProofGallery.jsx`. ConfirmModal props (`title/message/confirmLabel/confirmCls`) match between `App.jsx` and the component.
- **Placeholders:** none — every code step is complete.
