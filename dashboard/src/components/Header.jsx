import React from 'react';

export default function Header({ lanes, onAddLane }) {
  const n = s => lanes.filter(l => l.status === s).length;
  const st = lanes.filter(l => l.stalled).length;
  const na = lanes.filter(l => l.needs_action).length;

  return (
    <header>
      <h1>Feature Harness<small>parallel lanes — live watch</small></h1>
      <div className="counts">
        <span className="count"><b>{lanes.length}</b> lanes</span>
        {n('running') > 0 && <span className="count" style={{ color: '#7eb3ff' }}><b>{n('running')}</b> running</span>}
        {n('provisioning') > 0 && <span className="count" style={{ color: '#c4b5fd' }}><b>{n('provisioning')}</b> provisioning</span>}
        {n('blocked') > 0 && <span className="count" style={{ color: '#fcd34d' }}><b>{n('blocked')}</b> blocked</span>}
        {na > 0 && <span className="count" style={{ color: '#6ee7b7' }}><b>{na}</b> need you</span>}
        {st > 0 && <span className="count" style={{ color: '#ff9d9d' }}><b>{st}</b> stalled</span>}
      </div>
      <button className="add" onClick={e => { e.stopPropagation(); onAddLane(); }}>+ Add lane</button>
    </header>
  );
}
