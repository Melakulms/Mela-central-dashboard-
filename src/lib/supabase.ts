import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined
const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string | undefined

if (!url || !key) {
  throw new Error('Missing Supabase public configuration')
}

// GitHub Pages serves both MELA apps on the same origin. Supabase's default
// storage key would silently reuse the other app's logged-in session.
// Separate namespaces keep learner and central-admin sign-ins independent.
// Existing shared-key sessions intentionally require a fresh sign-in once.
export const AUTH_STORAGE_KEY = 'mela-central-supabase-auth-v1'
export const supabase = createClient(url, key, { auth: { storageKey: AUTH_STORAGE_KEY } })
