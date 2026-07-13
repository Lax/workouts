import { defineConfig } from 'vite'
import { svelte } from '@sveltejs/vite-plugin-svelte'
import { readFileSync } from 'fs'

const config = JSON.parse(readFileSync('config.json', 'utf-8'))
const input: Record<string, string> = {}
for (const key of Object.keys(config.pages))
  input[key] = `${key}.html`

export default defineConfig({
  plugins: [svelte()],
  resolve: {
    alias: {
      $lib: new URL('src/lib', import.meta.url).pathname,
    },
  },
  base: '',
  build: {
    outDir: 'dist',
    emptyOutDir: true,
    rollupOptions: {
      input,
      output: {
        entryFileNames: 'assets/[name]-[hash].js',
        chunkFileNames: 'assets/[name]-[hash].js',
        assetFileNames: 'assets/[name]-[hash][extname]',
      },
    },
  },
})
