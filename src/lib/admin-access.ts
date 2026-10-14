import type { SupabaseClient } from '@supabase/supabase-js'
import { getAdminMe, type AdminMe } from './admin-api'

export type AdminAccess = { kind: 'enroll' } | { kind: 'challenge'; factorId: string; factors: { id: string; label: string }[] } | { kind: 'ready'; admin: AdminMe }

// Network errors must never be interpreted as a missing MFA enrollment.
export async function resolveAdminAccess(client: SupabaseClient): Promise<AdminAccess> {
  const { data: assurance, error: assuranceError } = await client.auth.mfa.getAuthenticatorAssuranceLevel()
  if (assuranceError) throw assuranceError
  if (!assurance) throw new Error('Could not verify your session. Please retry.')
  if (assurance.currentLevel !== 'aal2') {
    const { data: factors, error: factorsError } = await client.auth.mfa.listFactors()
    if (factorsError) throw factorsError
    if (!factors) throw new Error('Could not load your authenticator. Please retry.')
    const verified = factors.totp.filter(item => item.status === 'verified')
    return verified.length
      ? { kind: 'challenge', factorId: verified[0].id,
          factors: verified.map((item, index) => ({
            id: item.id, label: item.friendly_name || `Authenticator ${index + 1}`,
          })) }
      : { kind: 'enroll' }
  }
  const admin = await getAdminMe(client)
  if (admin.mfa?.currentLevel !== 'aal2') throw new Error('MFA verification is required. Please sign in again.')
  return { kind: 'ready', admin }
}
