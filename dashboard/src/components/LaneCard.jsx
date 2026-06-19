import React from 'react';
import { fmtAge, fmtDur, prNum } from '../lib/format.js';

function LaneCardInner({ lane, selected, featureState, onSelect, onAction, onCreds }) {
  const viewing = featureState || null;
  const st = viewing ? (viewing.status || 'idle') : (lane.status || 'idle');
  const gd = (viewing ? (viewing.gate_decision || '') : (lane.gate_decision || '')).toUpperCase();
  const gcls = gd === 'GO' ? 'gate-go' : gd === 'NO-GO' ? 'gate-nogo' : 'gate-pending';
  const [age, acls] = fmtAge(lane.heartbeat_age_sec);
  const branch = lane.git_branch || lane.branch || '—';
  const head = lane.head || '—';
  const ci = lane.ci_status || '—';
  const url = lane.manual_test_url || '';
  const hasProgress = lane.progress != null;

  const stop = e => e.stopPropagation();

  return (
    <div className={`card ${st}${lane.stalled ? ' stalled-card' : ''}${selected ? ' sel' : ''}`}
         onClick={() => onSelect(lane.lane)}>
      <div className="top">
        <span className="lane">Lane {lane.lane}</span>
        <span className="badges">
          {lane.needs_action && <span className="badge b-needs"><span className="dot" />{' '}needs you</span>}
          {lane.stalled && <span className="badge b-stall"><span className="dot" />{' '}stalled</span>}
          <span className={`badge b-${st}`}><span className="dot" />{' '}{st}</span>
        </span>
      </div>
      <div className="feat">
        {viewing
          ? <>{viewing.feature_title || lane.feature_title} <span style={{ fontSize: '10px', color: 'var(--faint)' }}>(archived)</span></>
          : (lane.feature_title || <span className="none">idle — no feature assigned</span>)}
      </div>
      <div className="prog">
        <span className={`stagechip${hasProgress ? '' : ' q'}`}>{viewing ? viewing.stage || lane.stage : lane.stage}</span>
        <div className="bar"><i style={{ width: `${lane.progress || 0}%` }} /></div>
        <span className="pct">{hasProgress ? `${lane.progress}%` : ''}</span>
        {!viewing && lane.stage_age_sec != null &&
          <span title="time on current phase"
            style={{ fontSize: '10px', color: 'var(--faint)', marginLeft: '6px', whiteSpace: 'nowrap' }}>
            {'⏱'} {fmtDur(lane.stage_age_sec)}</span>}
      </div>
      <div className="meta">
        <span className={`chip ${lane.api_up ? 'up' : 'dn'}`} title={`lane API :800${lane.lane}`}
          style={viewing ? { opacity: 0.35 } : undefined}>
          <span className="dot" />api
        </span>
        <span className={`chip ${lane.fe_up ? 'up' : 'dn'}`} title={`lane FE :300${lane.lane}`}
          style={viewing ? { opacity: 0.35 } : undefined}>
          <span className="dot" />fe
        </span>
        <span className={`gchip ${gcls}`} title="senior gate decision">
          {'\u{1F6A6}'} {gd || '—'}
        </span>
        <span className={`right ${acls}`} title="heartbeat age"
          style={viewing ? { opacity: 0.35 } : undefined}>
          {'♥'} {age}
        </span>
      </div>
      <div className="ln" title={branch} style={viewing ? { opacity: 0.35 } : undefined}><span className="ic">{'⎋'}</span>{branch}</div>
      <div className="ln" title={head} style={viewing ? { opacity: 0.35 } : undefined}><span className="ic">{'●'}</span>{head}</div>
      <div className="ln" title={`CI — ${ci}`} style={viewing ? { opacity: 0.35 } : undefined}><span className="ic">CI</span>{ci}</div>
      <div className="metalinks">
        {(viewing ? viewing.pr_url : lane.pr_url)
          ? <a href={viewing ? viewing.pr_url : lane.pr_url} target="_blank" rel="noreferrer" onClick={stop}>{prNum(viewing ? viewing.pr_url : lane.pr_url)} {'↗'}</a>
          : <span className="gate-pending">{'—'}</span>}
        {(viewing ? viewing.ticket_url : lane.ticket_url)
          ? <a href={viewing ? viewing.ticket_url : lane.ticket_url} target="_blank" rel="noreferrer" onClick={stop}>{'\u{1F3AB}'} ticket {'↗'}</a>
          : <span className="gate-pending">{'\u{1F3AB}'} {'—'}</span>}
        <a href={url} target="_blank" rel="noreferrer" onClick={stop}>
          {'\u{1F310}'} {url.replace('http://localhost', '')} {'↗'}
        </a>
      </div>
      {!viewing && lane.needs_action && <div className="needs-line">{'\u{1F64B}'} {lane.needs_action}</div>}
      {(viewing ? viewing.notes : lane.notes) && <div className="notes">{viewing ? viewing.notes : lane.notes}</div>}
      <div className="actions">
        <button onClick={e => { stop(e); onAction(lane.lane, 'up'); }} title="boot / rebuild this lane's stack">{'▶'} up</button>
        <button onClick={e => { stop(e); onAction(lane.lane, 'down'); }} title="stop this lane's stack">{'■'} down</button>
        <button onClick={e => { stop(e); onAction(lane.lane, 'clear'); }} title="reset the status fields only">{'\u{1F9F9}'} clear</button>
        <button onClick={e => { stop(e); onCreds(lane.lane, 'agents'); }} title="re-push harness templates">{'♻'} agents</button>
        <button onClick={e => { stop(e); onCreds(lane.lane, 'creds'); }} title="edit accounts">{'\u{1F511}'} creds</button>
        <span className="spacer" />
        <button className="warn" onClick={e => { stop(e); onAction(lane.lane, 'reset'); }} title="clean dev + fresh DB">{'⟳'} reset</button>
        <button className="warn" onClick={e => { stop(e); onAction(lane.lane, 'remove'); }} title="delete lane">{'\u{1F5D1}'}</button>
      </div>
    </div>
  );
}

export default React.memo(LaneCardInner, (prev, next) => {
  if (prev.selected !== next.selected) return false;
  if (prev.featureState !== next.featureState) return false;
  const { lane: pl } = prev;
  const { lane: nl } = next;
  const { heartbeat_age_sec: _a, last_heartbeat: _b, stage_age_sec: _e, ...pr } = pl;
  const { heartbeat_age_sec: _c, last_heartbeat: _d, stage_age_sec: _f, ...nr } = nl;
  return JSON.stringify(pr) === JSON.stringify(nr);
});
