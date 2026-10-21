import { defineConfig, loadEnv } from 'vite'
import react from '@vitejs/plugin-react'

/** Limit the admin CSP's API connection origin to the selected build environment. */
const STAGING = 'https://tungqfmypuwzeyrtaseh.supabase.co'
const PRODUCTION = 'https://duizgtmbptmlbyipreqg.supabase.co'
export default defineConfig(({ mode }) => {
  // No staging endpoint is silently selected; CI's normal build remains production.
  const selected = (loadEnv(mode, '.', 'VITE_').VITE_SUPABASE_URL || '').replace(/\/$/, '')
  return {
    base: '/Mela-central-dashboard-/',
    plugins: [
      react(),
      {
        name: 'staging-supabase-csp',
        transformIndexHtml(html) {
          if (selected !== STAGING) return html
          const live = PRODUCTION + ' ' + PRODUCTION.replace('https:', 'wss:')
          const stage = STAGING + ' ' + STAGING.replace('https:', 'wss:')
          return html.replace(live, stage)
        },
      },
    ],
  }
})
