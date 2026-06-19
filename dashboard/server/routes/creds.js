import { Router } from 'express';
import { credsCurrent } from '../services/creds.js';

const router = Router();

router.get('/api/lane/:n(\\d)/creds-current', (req, res) => {
  try {
    res.json(credsCurrent(parseInt(req.params.n, 10)));
  } catch (e) {
    res.status(500).json({ ok: false, error: e.message });
  }
});

export default router;
