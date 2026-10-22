// @vitest-environment jsdom
import { beforeEach, afterEach, describe, it, expect, vi } from 'vitest'
const { createSpy } = vi.hoisted(() => ({ createSpy: vi.fn(() => ({ auth: {} })) }))
vi.mock('@supabase/supabase-js', () => ({ createClient: createSpy }))
import { createAdminClient } from '../src/lib/admin-api'

describe('Isolated staging Admin tab session', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.stubEnv('VITE_SUPABASE_PUBLISHABLE_KEY', 'sb_publishable_public_test_only')
  })
  afterEach(() => { vi.unstubAllEnvs(); sessionStorage.clear() })
  it('uses sessionStorage only on the exact staging project', () => {
    vi.stubEnv('VITE_SUPABASE_URL', 'https://tungqfmypuwzeyrtaseh.supabase.co')
    createAdminClient()
    expect(createSpy).toHaveBeenCalledWith(
      'https://tungqfmypuwzeyrtaseh.supabase.co',
      'sb_publishable_public_test_only',
      expect.objectContaining({auth:expect.objectContaining({
        persistSession:true,storage:window.sessionStorage,
        storageKey:'mela-staging-scholarship-tab-v1',
      })}),
    )
  })
  it('retains memory-only authentication for the production project', () => {
    vi.stubEnv('VITE_SUPABASE_URL', 'https://duizgtmbptmlbyipreqg.supabase.co')
    createAdminClient()
    const config = createSpy.mock.calls[0][2] as any
    expect(config.auth.persistSession).toBe(false)
    expect(config.auth.storage).toBeUndefined()
    expect(config.auth.storageKey).toBe('mela-central-supabase-auth-v1')
  })
  it('does not persist for lookalike origins', () => {
    vi.stubEnv('VITE_SUPABASE_URL', 'https://tungqfmypuwzeyrtaseh.supabase.co.evil.example')
    createAdminClient()
    expect((createSpy.mock.calls[0][2] as any).auth.persistSession).toBe(false)
  })
})
