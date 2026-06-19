import { useState, useRef, useCallback, useEffect } from 'react';
import { fetchReviews } from '../lib/api.js';

export function useReviews(selectedLane, lanes) {
  const [reviews, setReviews] = useState(null);
  const cacheKeyRef = useRef('');
  const cacheTxtRef = useRef('');
  const seqRef = useRef(0);

  const loadReviews = useCallback(async (n, force) => {
    if (n == null) return;
    const seq = ++seqRef.current;
    try {
      const d = await fetchReviews(n);
      if (seq !== seqRef.current) return; // stale response
      const lane = (lanes || []).find(l => l.lane === n) || {};
      const na = lane.needs_action || '';
      const key = String(n);
      const txt = JSON.stringify(d) + na;
      if (!force && cacheKeyRef.current === key && cacheTxtRef.current === txt) return;
      cacheKeyRef.current = key;
      cacheTxtRef.current = txt;
      setReviews(d);
    } catch { /* ignore */ }
  }, [lanes]);

  useEffect(() => {
    if (selectedLane != null) {
      const lane = (lanes || []).find(l => l.lane === selectedLane);
      if (lane && lane.mode === 'pr-review') loadReviews(selectedLane, true);
    }
  }, [selectedLane]);

  return { reviews, loadReviews };
}
