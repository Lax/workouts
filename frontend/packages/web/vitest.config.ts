import { defineConfig } from 'vitest/config'

export default defineConfig({
  esbuild: {
    jsx: 'automatic',
  },
  test: {
    environment: 'jsdom',
    include: ['tests/**/*.test.{ts,tsx}'],
    css: true,
    server: {
      deps: {
        inline: [/@git-fit/],
      },
    },
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json-summary'],
      reportsDirectory: 'coverage',
      allowExternal: true,
      include: ['**/src/**/*.{ts,tsx}'],
      exclude: ['**/*.d.ts'],
    },
  },
})
