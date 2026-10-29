import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { SupabaseClient } from '@supabase/supabase-js'
import { claimStagingOwnerAdmin } from '../src/lib/staging-owner-bootstrap'

const fixtures = vi.hoisted(() => ({
  getUser: vi.fn(),
  getAuthenticatorAssuranceLevel: vi.fn(),
  rpc: vi.fn(),
}))
const client = {
  auth: {
    getUser: fixtures.getUser,
    mfa: { getAuthenticatorAssuranceLevel: fixtures.getAuthenticatorAssuranceLevel },
  },
  rpc: fixtures.rpc,
} as unknown as SupabaseClient

beforeEach(() => {
  vi.resetAllMocks()
  fixtures.getUser.mockResolvedValue({
    data: { user: { email: 'melakuanteneh1@gmail.com', email_confirmed_at: '2026-10-29T00:00:00Z' } },
    error: null,
  })
  fixtures.getAuthenticatorAssuranceLevel.mockResolvedValue({ data: { currentLevel: 'aal2' }, error: null })
  fixtures.rpc.mockResolvedValue({ data: { success: true }, error: null })
})

describe('staging first-owner bootstrap handoff', () => {
  it('refuses every other email without touching an administrator RPC', async () => {
    fixtures.getUser.mockResolvedValue({ data: { user: { email: 'other@example.com', email_confirmed_at: '2026-10-29' } }, error: null })
    await expect(claimStagingOwnerAdmin(client)).rejects.toThrow(/designated staging owner/)
    expect(fixtures.rpc).not.toHaveBeenCalled()
  })
  it('refuses unverified owner email before contacting the RPC', async () => {
    fixtures.getUser.mockResolvedValue({ data: { user: { email: 'melakuanteneh1@gmail.com', email_confirmed_at: null } }, error: null })
    await expect(claimStagingOwnerAdmin(client)).rejects.toThrow(/Confirm your owner email/)
    expect(fixtures.rpc).not.toHaveBeenCalled()
  })
  it('refuses AAL1 sessions', async () => {
    fixtures.getAuthenticatorAssuranceLevel.mockResolvedValue({ data: { currentLevel: 'aal1' }, error: null })
    await expect(claimStagingOwnerAdmin(client)).rejects.toThrow(/Google Authenticator/)
    expect(fixtures.rpc).not.toHaveBeenCalled()
  })
  it('honors a server-side bootstrap rejection rather than claiming success', async () => {
    fixtures.rpc.mockResolvedValue({ data: { success: false, code: 'bootstrap_already_consumed' }, error: null })
    await expect(claimStagingOwnerAdmin(client)).rejects.toThrow(/bootstrap_already_consumed/)
    expect(fixtures.rpc).toHaveBeenCalledWith('claim_staging_first_super_admin')
  })
  it('does not mask backend network or RLS failures', async () => {
    fixtures.rpc.mockResolvedValue({ data: null, error: new Error('backend inaccessible') })
    await expect(claimStagingOwnerAdmin(client)).rejects.toThrow(/backend inaccessible/)
  })
  it('calls only the audited one-use RPC for a confirmed AAL2 owner session', async () => {
    await expect(claimStagingOwnerAdmin(client)).resolves.toBeUndefined()
    expect(fixtures.rpc).toHaveBeenCalledTimes(1)
    expect(fixtures.rpc).toHaveBeenCalledWith('claim_staging_first_super_admin')
  })
})
