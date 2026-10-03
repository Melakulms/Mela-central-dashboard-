import type { SupabaseClient } from '@supabase/supabase-js'
import { getAdminMe, type AdminMe } from './admin-api'

export type AdminAccess = { kind: 'enroll' } | { kind: 'challenge'; factorId: string } | { kind: 'ready'; admin: AdminMe }

// Network errors must never be interpreted as a missing MFA enrollment.
export async function resolveAdminAccess(client: SupabaseClient): Promise<AdminAccess> {
  const { data: assurance, error: assuranceError } = await client.auth.mfa.getAuthenticatorAssuranceLevel()
  if (assuranceError) throw assuranceError
  if (!assurance) throw new Error('Could not verify your session. Please retry.')
  if (assurance.currentLevel !== 'aal2') {
    const { data: factors, error: factorsError } = await client.auth.mfa.listFactors()
    if (factorsError) throw factorsError
    if (!factors) throw new Error('Could not load your authenticator. Please retry.')
    const factor = factors.totp.find(item => item.status === 'verified')
    return factor ? { kind: 'challenge', factorId: factor.id } : { kind: 'enroll' }
  }
  const admin = await getAdminMe(client)
  if (admin.mfa?.currentLevel !== 'aal2') throw new Error('MFA verification is required. Please sign in again.')
  return { kind: 'ready', admin }
}
