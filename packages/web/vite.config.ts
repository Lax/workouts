import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { readFileSync } from 'fs'

const raw = readFileSync('config.json', 'utf-8')
const config = JSON.parse(raw)
const entries = config.entries ?? { index: config.theme }
const input: Record<string, string> = {}

for (const key of Object.keys(entries)) {
  input[key] = `${key}.html`
}

export default defineConfig({
  plugins: [react()],
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
        manualChunks(id) {
          if (id.includes('node_modules/leaflet')) return 'leaflet'
          if (id.includes('node_modules/echarts')) return 'echarts'
          if (id.includes('node_modules/react') || id.includes('node_modules/zustand')) return 'react'
          if (id.includes('node_modules')) return 'vendor'
        },
      },
    },
  },
})
