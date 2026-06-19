import React from 'react';
import PipelineEdges from './PipelineEdges.jsx';
import PipelineNodes from './PipelineNodes.jsx';
import { phaseIdx } from '../lib/constants.js';
import { fmtDur } from '../lib/format.js';

export default function PipelineMap({ lane, config, archived }) {
  const isReview = lane.mode === 'pr-review';
  const hasProgress = phaseIdx(lane.stage) >= 0;

  return (
    <div className="mapwrap">
      <div className="maphead">
        <b>Lane {lane.lane}</b>
        <span className={`stagechip${isReview || !hasProgress ? ' q' : ''}`}>{lane.stage}</span>
        <span style={{ color: 'var(--dim)' }}>{lane.feature_title || '(idle)'}</span>
        {archived && <span className="pf-prev" title="viewing a past feature — read-only snapshot">past feature</span>}
        {!archived && !isReview && hasProgress && lane.stage_age_sec != null &&
          <span style={{ color: 'var(--faint)' }} title="time on current phase">
            {'⏱'} on <b>{lane.stage}</b> for {fmtDur(lane.stage_age_sec)}</span>}
        <span className="hint">{archived ? 'pick “• current” to return to the live feature' : 'click a card to map another lane'}</span>
      </div>
      <svg viewBox="0 -12 1390 254" xmlns="http://www.w3.org/2000/svg">
        <defs>
          <marker id="ad" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6.5" markerHeight="6.5" orient="auto">
            <path d="M0,0L10,5L0,10z" fill="#39424e" /></marker>
          <marker id="ag" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6.5" markerHeight="6.5" orient="auto">
            <path d="M0,0L10,5L0,10z" fill="#2ea27c" /></marker>
          <marker id="ac" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto">
            <path d="M0,0L10,5L0,10z" fill="#8a93a3" /></marker>
          <marker id="ab" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto">
            <path d="M0,0L10,5L0,10z" fill="#60a5fa" /></marker>
          <marker id="acr" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto">
            <path d="M0,0L10,5L0,10z" fill="#f87171" /></marker>
        </defs>
        <PipelineEdges lane={lane} />
        <PipelineNodes lane={lane} config={config} />
      </svg>
      <div className="legend">
        <span><i className="ld g" />done</span>
        <span><i className="ld b" />current</span>
        <span><i className="ld w" />{'⚠ passed without evidence — check it'}</span>
        <span><i className="ld n" />pending</span>
        <span style={{ color: '#fbbf24' }}>{'↻ self-resolves & continues (hover)'}</span>
        <span style={{ marginLeft: 'auto', color: 'var(--faint)' }}>{'red dashed = fail paths → fix · blue = re-entry'}</span>
      </div>
    </div>
  );
}
