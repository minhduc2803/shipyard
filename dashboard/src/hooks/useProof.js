import { useState, useRef, useCallback, useEffect } from 'react';
import { fetchProof } from '../lib/api.js';

export function useProof(selectedLane, lanes) {
  const [proof, setProof] = useState(null);
  const cacheKeyRef = useRef('');
  const cacheTxtRef = useRef('');
  const selRef = useRef({});        // per-lane selected feature slug
  const manualRef = useRef({});     // per-lane manual pick flag
  const curRef = useRef({});        // per-lane current feature slug
  const titleRef = useRef({});      // per-lane feature_title
  const seqRef = useRef(0);         // cancellation token

  const loadProof = useCallback(async (n, force) => {
    if (n == null) return;
    const seq = ++seqRef.current;
    try {
      const d = await fetchProof(n);
      if (seq !== seqRef.current) return; // stale response
      const lane = (lanes || []).find(l => l.lane === n) || {};
      // Current feature = what the SERVER derived from state (.active / _pending) —
      // the same source the lane card reads. Fall back to parsing the branch only if
      // the server didn't supply it (older payloads).
      const m = /feat\/([^ +]+)/.exec(lane.git_branch || '');
      d._cur = d.current || (m ? m[1] : '');

      const key = String(n);
      const txt = JSON.stringify(d);
      if (!force && cacheKeyRef.current === key && cacheTxtRef.current === txt) return;
      cacheKeyRef.current = key;
      cacheTxtRef.current = txt;

      const curTitle = lane.feature_title || '';
      if (curTitle !== (titleRef.current[n] || '')) {
        titleRef.current[n] = curTitle;
        manualRef.current[n] = false;
      }
      if (d._cur !== curRef.current[n]) {
        curRef.current[n] = d._cur;
        manualRef.current[n] = false;
      }

      const has = s => !!s && d.features.some(f => f.slug === s);
      if (!(manualRef.current[n] && (has(selRef.current[n]) || selRef.current[n] === d._cur)))
        selRef.current[n] = d._cur || (d.features[0] && d.features[0].slug) || '';

      setProof(d);
    } catch { /* ignore */ }
  }, [lanes]);

  const selectFeature = useCallback((n, slug) => {
    selRef.current[n] = slug;
    manualRef.current[n] = true;
    setProof(prev => prev ? { ...prev } : prev);
  }, []);

  const selectedSlug = selectedLane != null ? (selRef.current[selectedLane] || '') : '';

  useEffect(() => {
    if (selectedLane != null) loadProof(selectedLane, true);
  }, [selectedLane]);

  return { proof, loadProof, selectFeature, selectedSlug };
}
