import { execFileSync } from 'child_process';
import path from 'path';
import fs from 'fs';
import { LANES_ROOT } from './config.js';

export function git(n, ...args) {
  const d = path.join(LANES_ROOT, `lane${n}`);
  if (!fs.existsSync(path.join(d, '.git'))) return '';
  try {
    return execFileSync('git', ['-C', d, ...args], { timeout: 3000, encoding: 'utf8' }).trim();
  } catch {
    return '';
  }
}
