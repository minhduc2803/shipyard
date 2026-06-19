import express from 'express';
import path from 'path';
import { fileURLToPath } from 'url';
import lanesRoutes from './routes/lanes.js';
import proofRoutes from './routes/proof.js';
import credsRoutes from './routes/creds.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const app = express();

app.use(express.json());

app.use((req, res, next) => {
  const origin = req.headers.origin;
  if (origin && !origin.startsWith(`http://127.0.0.1:`) && !origin.startsWith(`http://localhost:`)) {
    return res.status(403).end('Forbidden');
  }
  next();
});

app.use(lanesRoutes);
app.use(proofRoutes);
app.use(credsRoutes);

// Serve built React frontend
const dist = path.join(__dirname, '..', 'dist');
app.use(express.static(dist));
app.get('*', (_req, res) => {
  res.sendFile(path.join(dist, 'index.html'));
});

const port = parseInt(process.argv[2] || process.env.DASHBOARD_PORT || '8090', 10);
app.listen(port, '127.0.0.1', () => {
  console.log(`harness dashboard: http://127.0.0.1:${port}`);
});
