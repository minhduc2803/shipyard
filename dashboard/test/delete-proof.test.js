// deleteProof() must remove screenshots at three granularities (files / group /
// whole feature), enforce realpath containment (no traversal), refuse the ticket
// group, prune empty group dirs, and never touch state JSON.
import { describe, it, expect, beforeAll, beforeEach, afterAll } from 'vitest';
import fs from 'fs';
import os from 'os';
import path from 'path';

let tmp, deleteProof;

function proofDir(slug, group, lane = 3) {
  return path.join(process.env.LANES_ROOT, `lane${lane}`, '.playwright-mcp', 'proof', slug, group);
}
function writeProof(slug, group, file, lane = 3) {
  const d = proofDir(slug, group, lane);
  fs.mkdirSync(d, { recursive: true });
  fs.writeFileSync(path.join(d, file), 'x');
}
function writeState(slug, obj, lane = 3) {
  const d = path.join(process.env.HARNESS_ROOT, 'state', `lane${lane}`);
  fs.mkdirSync(d, { recursive: true });
  fs.writeFileSync(path.join(d, `${slug}.json`), JSON.stringify(obj));
}

beforeAll(async () => {
  // config.js captures LANES_ROOT/HARNESS_ROOT at import time, so the root must be
  // stable across tests; only the fixtures inside it are rebuilt per test.
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'harness-del-'));
  process.env.HARNESS_ROOT = path.join(tmp, 'harness');
  process.env.LANES_ROOT = path.join(tmp, 'lanes');
  ({ deleteProof } = await import('../server/services/proof.js'));
});
afterAll(() => { try { fs.rmSync(tmp, { recursive: true, force: true }); } catch { /* ignore */ } });

beforeEach(() => {
  // fresh fixtures inside the stable root
  fs.rmSync(path.join(process.env.LANES_ROOT, 'lane3'), { recursive: true, force: true });
  fs.rmSync(path.join(process.env.HARNESS_ROOT, 'state', 'lane3'), { recursive: true, force: true });

  writeProof('csv-export', 'qc-local', '01-shot.png');
  writeProof('csv-export', 'qc-local', '02-shot.png');
  writeProof('csv-export', 'qc-dev', '01-dev.png');
  // a ticket report dir (must never be deleted)
  const tdir = proofDir('csv-export', 'ticket');
  fs.mkdirSync(tdir, { recursive: true });
  fs.writeFileSync(path.join(tdir, 'REPORT.html'), '<html>');
  // a state record (must never be deleted)
  writeState('csv-export', { stage: 'done', feature_title: 'CSV export' });
});

describe('deleteProof', () => {
  it('deletes named image files within a group and returns the count', () => {
    const r = deleteProof(3, { slug: 'csv-export', group: 'qc-local', images: ['01-shot.png'] });
    expect(r).toEqual({ ok: true, deleted: 1 });
    expect(fs.existsSync(path.join(proofDir('csv-export', 'qc-local'), '01-shot.png'))).toBe(false);
    expect(fs.existsSync(path.join(proofDir('csv-export', 'qc-local'), '02-shot.png'))).toBe(true);
  });

  it('prunes a group dir that becomes empty after deleting its last file', () => {
    deleteProof(3, { slug: 'csv-export', group: 'qc-dev', images: ['01-dev.png'] });
    expect(fs.existsSync(proofDir('csv-export', 'qc-dev'))).toBe(false);
  });

  it('deletes a whole group dir', () => {
    const r = deleteProof(3, { slug: 'csv-export', group: 'qc-local' });
    expect(r.deleted).toBe(2);
    expect(fs.existsSync(proofDir('csv-export', 'qc-local'))).toBe(false);
    expect(fs.existsSync(proofDir('csv-export', 'qc-dev'))).toBe(true);
  });

  it('clears all image groups for a feature but keeps ticket and state', () => {
    const r = deleteProof(3, { slug: 'csv-export' });
    expect(r.deleted).toBe(3);
    expect(fs.existsSync(proofDir('csv-export', 'qc-local'))).toBe(false);
    expect(fs.existsSync(proofDir('csv-export', 'qc-dev'))).toBe(false);
    // ticket report + state untouched
    expect(fs.existsSync(path.join(proofDir('csv-export', 'ticket'), 'REPORT.html'))).toBe(true);
    expect(fs.existsSync(path.join(process.env.HARNESS_ROOT, 'state', 'lane3', 'csv-export.json'))).toBe(true);
  });

  it('refuses to delete the ticket group', () => {
    expect(() => deleteProof(3, { slug: 'csv-export', group: 'ticket' })).toThrow();
    expect(fs.existsSync(path.join(proofDir('csv-export', 'ticket'), 'REPORT.html'))).toBe(true);
  });

  it('rejects path traversal in slug, group, and image names', () => {
    expect(() => deleteProof(3, { slug: '../../etc' })).toThrow();
    expect(() => deleteProof(3, { slug: 'csv-export', group: '../qc-dev' })).toThrow();
    expect(() => deleteProof(3, { slug: 'csv-export', group: 'qc-local', images: ['../01-dev.png'] })).toThrow();
  });

  it('throws when the proof base or feature dir does not exist', () => {
    expect(() => deleteProof(9, { slug: 'csv-export' })).toThrow();
    expect(() => deleteProof(3, { slug: 'no-such-feature' })).toThrow();
  });
});
