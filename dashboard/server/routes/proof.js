import { Router } from 'express';
import path from 'path';
import { proofPayload, proofFile, deleteProof } from '../services/proof.js';
import { reviewsPayload } from '../services/reviews.js';

const router = Router();

router.get('/api/proof/:n(\\d)', (req, res) => {
  try {
    res.json(proofPayload(parseInt(req.params.n, 10)));
  } catch (e) {
    res.status(500).json({ ok: false, error: e.message });
  }
});

router.get('/api/reviews/:n(\\d)', (req, res) => {
  try {
    res.json(reviewsPayload(parseInt(req.params.n, 10)));
  } catch (e) {
    res.status(500).json({ ok: false, error: e.message });
  }
});

router.delete('/api/proof/:n(\\d)', (req, res) => {
  try {
    res.json(deleteProof(parseInt(req.params.n, 10), req.body || {}));
  } catch (e) {
    res.status(400).json({ ok: false, error: e.message });
  }
});

router.get('/proof/:n(\\d)/*', (req, res) => {
  const n = parseInt(req.params.n, 10);
  const relpath = decodeURIComponent(req.params[0]);
  const p = proofFile(n, relpath);
  if (!p) return res.status(404).send('not found');
  const ext = path.extname(p).toLowerCase();
  const ct = ext === '.html' ? 'text/html; charset=utf-8'
           : ext === '.png' ? 'image/png' : 'image/jpeg';
  res.type(ct).sendFile(p);
});

export default router;
