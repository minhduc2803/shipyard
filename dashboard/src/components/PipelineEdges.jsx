import React from 'react';
import { NODES, MAINY, BUS, BLKY, TKT } from '../lib/constants.js';
import { phaseIdx } from '../lib/constants.js';

export default function PipelineEdges({ lane }) {
  const cur = phaseIdx(lane.stage);
  const isDone = lane.stage === 'done';
  const els = [];

  // main forward edges
  for (let i = 0; i < NODES.length - 1; i++) {
    const x1 = NODES[i][2] + 16, x2 = NODES[i + 1][2] - 16;
    const done = isDone || i < cur;
    els.push(<line key={`e${i}`} x1={x1} y1={MAINY} x2={x2} y2={MAINY}
      stroke={done ? '#2ea27c' : '#39424e'} strokeWidth="1.6"
      markerEnd={`url(#a${done ? 'g' : 'd'})`} />);
  }

  // edge labels
  els.push(<text key="lgo" className="e-label" x="946" y={MAINY - 8} textAnchor="middle">GO</text>);
  els.push(<text key="lmc" className="e-label" x="1292" y="44" textAnchor="middle">merged / closed</text>);

  // fix loop bus
  els.push(<path key="bus" d={`M1249,${BUS} H320`} fill="none" stroke="#9aa5b4"
    strokeWidth="1.3" strokeDasharray="5 3" opacity=".6" markerEnd="url(#ac)" />);

  // vertical drops to bus
  for (const x of [559, 645, 731, 817, 903, 1163, 1249]) {
    els.push(<path key={`vd${x}`} d={`M${x},${MAINY + 14} V${BUS - 4}`} fill="none"
      stroke="#f87171" strokeWidth="1.3" strokeDasharray="4 3" opacity=".6" markerEnd="url(#acr)" />);
  }

  // gates -> fix drop
  els.push(<path key="gfix" d={`M301,${MAINY + 14} V${BUS - 21}`} fill="none"
    stroke="#f87171" strokeWidth="1.3" strokeDasharray="4 3" opacity=".6" markerEnd="url(#acr)" />);

  // fix return arc
  els.push(<path key="ret" d={`M285,${BUS} H258 V96 H293 V84`} fill="none"
    stroke="#60a5fa" strokeWidth="1.7" strokeDasharray="5 3" opacity=".95" markerEnd="url(#ab)" />);
  els.push(<text key="lret" className="e-label" x="250" y="140" textAnchor="end"
    style={{ fill: '#60a5fa' }}>{'↻ re-enter stage 2'}</text>);

  // blocked stub (gate -> "blocked — needs you"; an escalation, not an automatic cap)
  els.push(<circle key="blkc" cx="903" cy={BLKY} r="2" fill="#f87171" opacity=".7" />);
  els.push(<path key="blkp" d={`M903,${BLKY} H932`} fill="none"
    stroke="#f87171" strokeWidth="1.3" strokeDasharray="4 3" opacity=".7" markerEnd="url(#acr)" />);

  // push dev -> integrate conflict arc
  els.push(<path key="cflct" d={`M979,${MAINY - 14} V24 H473 V${MAINY - 18}`} fill="none"
    stroke="#f87171" strokeWidth="1.3" strokeDasharray="4 3" opacity=".55" markerEnd="url(#acr)" />);
  els.push(<text key="lcflct" className="e-label" x="731" y="18" textAnchor="middle">
    {'re-merge conflicts → re-integrate'}</text>);

  // ticket fork
  els.push(<path key="tkt" d={`M999,${MAINY - 13} V${TKT[3]} H1016`} fill="none"
    stroke="#9aa5b4" strokeWidth="1.3" strokeDasharray="5 3" opacity=".6" markerEnd="url(#ac)" />);

  return <>{els}</>;
}
