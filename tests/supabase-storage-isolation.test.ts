import { expect, it, vi } from 'vitest'

const { createClient } = vi.hoisted(() => ({
  createClient: vi.fn(() => ({ auth: {} })),
}))
vi.mock('@supabase/supabase-js', () => ({ createClient }))

it('isolates this app session from the other MELA app on the shared GitHub Pages origin', async () => {
  vi.stubEnv('VITE_SUPABASE_URL', 'https://example.supabase.co')
  vi.stubEnv('VITE_SUPABASE_PUBLISHABLE_KEY', 'sb_publishable_test')
  try {
    const { AUTH_STORAGE_KEY } = await import('../src/lib/supabase')
    expect(AUTH_STORAGE_KEY).toBe('mela-central-supabase-auth-v1')
    expect(AUTH_STORAGE_KEY).not.toBe('mela-users-supabase-auth-v1')
    expect(createClient).toHaveBeenCalledWith(
      'https://example.supabase.co',
      'sb_publishable_test',
      { auth: { storageKey: 'mela-central-supabase-auth-v1' } },
    )
  } finally {
    vi.unstubAllEnvs()
  }
})
