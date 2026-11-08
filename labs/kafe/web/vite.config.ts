import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      '/events': {
        target: 'http://127.0.0.1:4242',
        changeOrigin: true,
      },
      '/stream': {
        target: 'http://127.0.0.1:4242',
        changeOrigin: true,
      },
      '/chat': {
        target: 'http://127.0.0.1:4242',
        changeOrigin: true,
      },
      '/tasks': {
        target: 'http://127.0.0.1:4242',
        changeOrigin: true,
      },
      '/artifacts': {
        target: 'http://127.0.0.1:4242',
        changeOrigin: true,
      },
      '/nodes': {
        target: 'http://127.0.0.1:4242',
        changeOrigin: true,
      },
      '/quota': {
        target: 'http://127.0.0.1:4242',
        changeOrigin: true,
      },
      '/projects': {
        target: 'http://127.0.0.1:4242',
        changeOrigin: true,
      },
      '/conversations': {
        target: 'http://127.0.0.1:4242',
        changeOrigin: true,
      },
      '/power': {
        target: 'http://127.0.0.1:4242',
        changeOrigin: true,
      },
      '/swarm': {
        target: 'http://127.0.0.1:4242',
        changeOrigin: true,
      },
    },
  },
  build: {
    outDir: 'dist',
    sourcemap: true,
  },
});
