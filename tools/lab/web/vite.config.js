import { defineConfig } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';

// Built into ../webdist/app and compiled into the lab binary (studio.go).
// `npm run dev` proxies to a running `make lab`; the token is then read
// from the lab page (see lib/api.js).
const lab = 'http://127.0.0.1:8765';

export default defineConfig({
  plugins: [svelte()],
  base: '/video/',
  build: { outDir: '../webdist/app', emptyOutDir: true },
  server: { proxy: { '/api': lab, '/media': lab } },
});
