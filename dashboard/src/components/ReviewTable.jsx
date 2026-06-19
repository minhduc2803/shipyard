import React from 'react';
import { fmtWhen } from '../lib/format.js';

const ICON = { reviewed: '\u{1F4DD}', commented: '\u{1F4DD}', responded: '\u{1F4AC}', approved: '✅', drafted: '\u{1F4C4}', skipped: '⏭️', error: '⚠️' };

export default function ReviewTable({ reviews, needsAction, config }) {
  const repo = config?.repo || '';

  if (!reviews) return <span className="pf-empty">loading review history…</span>;

  const events = reviews.events || [];

  return (
    <div className="reviews">
      {needsAction && <div className="needs-banner">{'\u{1F64B}'} needs you — {needsAction}</div>}
      {!events.length ? (
        <span className="pf-empty">{'\u{1F50E}'} no PR reviews yet — the loop will list them here as it posts feedback</span>
      ) : (
        <table className="rv">
          <thead><tr><th>when</th><th>PR</th><th>action</th><th>detail</th></tr></thead>
          <tbody>
            {events.map((e, i) => (
              <tr key={i}>
                <td className="rv-ts">{fmtWhen(e.ts)}</td>
                <td>
                  {repo
                    ? <a href={`https://github.com/${repo}/pull/${e.pr}`} target="_blank" rel="noreferrer">#{e.pr} {'↗'}</a>
                    : `#${e.pr}`}
                </td>
                <td>{ICON[e.action] || '•'} {e.action}</td>
                <td className="rv-d">{e.detail || ''}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}
