import { Router } from 'express';
import { lanesPayload } from '../services/state.js';
import { runAction } from '../services/actions.js';

const router = Router();

router.get('/api/lanes', async (_req, res) => {
  try {
    res.json(await lanesPayload());
  } catch (e) {
    res.status(500).json({ ok: false, error: e.message });
  }
});

router.post('/api/lane/:n(\\d)/:action', (req, res) => {
  const n = parseInt(req.params.n, 10);
  const { action } = req.params;
  try {
    const result = runAction(n, action, req.body || {});
    res.json(result !== null && typeof result === 'object' ? result : { ok: true });
  } catch (e) {
    res.status(500).json({ ok: false, error: e.message });
  }
});

router.post('/api/lanes/add', (req, res) => {
  try {
    const result = runAction(null, 'add', req.body || {});
    res.json(result !== null && typeof result === 'object' ? result : { ok: true });
  } catch (e) {
    res.status(500).json({ ok: false, error: e.message });
  }
});

export default router;
