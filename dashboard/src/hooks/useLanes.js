import { useState, useEffect, useRef, useCallback } from 'react';
import { fetchLanes } from '../lib/api.js';

function volSig(data) {
  return JSON.stringify(data.lanes.map(l => {
    const { heartbeat_age_sec, last_heartbeat, ...rest } = l;
    return rest;
  }));
}

export function useLanes() {
  const [data, setData] = useState(null);
  const sigRef = useRef('');
  const dataRef = useRef(null);
  const [forceCount, setForceCount] = useState(0);

  const refreshNow = useCallback(() => {
    sigRef.current = '';
    setForceCount(c => c + 1);
  }, []);

  useEffect(() => {
    let active = true;

    async function tick() {
      if (!active) return;
      try {
        const d = await fetchLanes();
        if (!active) return;
        const sig = volSig(d);
        if (sig !== sigRef.current) {
          sigRef.current = sig;
          dataRef.current = d;
          setData({ ...d });
        } else {
          // volatile-only update: patch heartbeat ages in place
          dataRef.current = d;
          setData(prev => {
            if (!prev) return d;
            const updated = { ...d, lanes: d.lanes.map(l => ({ ...l })) };
            return updated;
          });
        }
      } catch { /* transient fetch errors recover on next tick */ }
    }

    tick();
    const id = setInterval(tick, 3000);
    return () => { active = false; clearInterval(id); };
  }, [forceCount]);

  return { data, refreshNow };
}
