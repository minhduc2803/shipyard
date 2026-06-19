import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

const backendPort = process.env.DASHBOARD_PORT || '8090';
const backend = `http://127.0.0.1:${backendPort}`;

export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      '/api': backend,
      '/proof': backend,
    },
  },
  build: {
    outDir: 'dist',
  },
});
