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
