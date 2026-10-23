import { rmSync } from 'node:fs'
import { defineConfig, type Plugin } from 'vite'
import react from '@vitejs/plugin-react'

// Mock data is for development only; keep it out of the deployed bundle unless asked.
const stripMock = (): Plugin => ({
  name: 'strip-mock',
  apply: 'build',
  closeBundle() {
    if (process.env.VITE_INCLUDE_MOCK !== '1') rmSync('dist/mock', { recursive: true, force: true })
  },
})

export default defineConfig({
  base: './',
  plugins: [react(), stripMock()],
  build: { chunkSizeWarningLimit: 900 },
})
