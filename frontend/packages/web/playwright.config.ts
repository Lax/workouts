import { defineConfig } from '@playwright/test'

export default defineConfig({
  testDir: 'tests/e2e',
  webServer: {
    command: 'npx vite preview --port 4173',
    port: 4173,
    reuseExistingServer: true,
    cwd: '.',
  },
  use: {
    baseURL: 'http://localhost:4173',
  },
})
