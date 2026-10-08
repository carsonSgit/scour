/// <reference types="vitest" />
import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import { fumadocsMdx } from 'fumadocs-mdx/vite'

export default defineConfig({
  base: '/scour/',
  plugins: [fumadocsMdx(), tailwindcss(), react()],
  test: {
    environment: 'jsdom',
    include: ['tests/**/*.test.{ts,tsx}'],
  },
})
