import { execSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

const raw = readFileSync('config.json', 'utf-8')
const config = JSON.parse(raw)
const entries = config.entries ?? { index: config.theme }
const input: Record<string, string> = {}

for (const key of Object.keys(entries)) {
  input[key] = `${key}.html`
}

function collectVersionsPlugin(): import('vite').Plugin {
  return {
    name: 'collect-versions',
    buildStart() {
      const script = resolve(__dirname, '../../scripts/collect-versions.mjs')
      execSync(`node ${script}`, { cwd: resolve(__dirname, '../..'), stdio: 'inherit' })
    },
  }
}

export default defineConfig({
  plugins: [collectVersionsPlugin(), react()],
  envPrefix: ['VITE_', 'GIT_FIT_'],
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
