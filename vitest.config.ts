import { defineConfig } from 'vitest/config'

export default defineConfig({
  test: {
    environment: 'jsdom',
    globals: false,
    include: ['packages/*/test/**/*.test.{ts,tsx}'],
    setupFiles: ['packages/theme-stats/test/setup.ts'],
  },
})
