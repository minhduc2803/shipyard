import React from 'react';
import LaneCard from './LaneCard.jsx';

export default function LaneGrid({ lanes, selectedLane, featureState, onSelect, onAction, onCreds }) {
  if (!lanes.length) {
    return <div className="grid"><div className="empty">No lanes yet — hit "+ Add lane" to provision one.</div></div>;
  }
  return (
    <div className="grid">
      {lanes.map(l => (
        <LaneCard key={l.lane} lane={l} selected={l.lane === selectedLane}
          featureState={l.lane === selectedLane ? featureState : null}
          onSelect={onSelect} onAction={onAction} onCreds={onCreds} />
      ))}
    </div>
  );
}
