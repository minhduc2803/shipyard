export function esc(s) {
  if (s == null) return '';
  return String(s).replace(/[&<>]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));
}

export function fmtAge(s) {
  if (s == null) return ['—', ''];
  const t = s < 60 ? s + 's'
    : s < 3600 ? Math.floor(s / 60) + 'm ' + (s % 60) + 's'
    : Math.floor(s / 3600) + 'h ' + Math.floor((s % 3600) / 60) + 'm';
  const cls = s < 120 ? 'hb-fresh' : s < 900 ? 'hb-warn' : 'hb-stale';
  return [t + ' ago', cls];
}

// Plain elapsed duration (no "ago") — used for time-on-current-phase.
export function fmtDur(s) {
  if (s == null) return '—';
  if (s < 60) return s + 's';
  if (s < 3600) return Math.floor(s / 60) + 'm ' + (s % 60) + 's';
  return Math.floor(s / 3600) + 'h ' + Math.floor((s % 3600) / 60) + 'm';
}

export function fmtWhen(iso) {
  try {
    const t = new Date(iso);
    const s = Math.round((Date.now() - t) / 1000);
    if (s < 60) return s + 's ago';
    if (s < 3600) return Math.floor(s / 60) + 'm ago';
    if (s < 86400) return Math.floor(s / 3600) + 'h ago';
    return Math.floor(s / 86400) + 'd ago';
  } catch {
    return iso;
  }
}

export function prNum(u) {
  const m = /\/pull\/(\d+)/.exec(u || '');
  return m ? '#' + m[1] : 'PR';
}
