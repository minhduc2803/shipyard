import fs from 'fs';
import path from 'path';
import { STATE_DIR } from './config.js';

export function reviewsPayload(n) {
  const f = path.join(STATE_DIR, `lane${n}-reviews.json`);
  let events = [];
  if (fs.existsSync(f)) {
    try { events = JSON.parse(fs.readFileSync(f, 'utf8')); } catch { events = []; }
  }
  events = [...events].reverse().slice(0, 60);
  return { lane: n, events };
}
