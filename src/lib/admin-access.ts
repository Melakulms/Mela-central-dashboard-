import type { SupabaseClient } from '@supabase/supabase-js'
import { getAdminMe, type AdminMe } from './admin-api'
import { isScholarshipStagingUrl } from './scholarship-staging'

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
  // The isolated staging guardian preview does not deploy the production admin API.
  // Ask the staging database for its existing MFA-enforced super-admin decision.
  // All guardian writes independently re-check the same backend policy.
  if (isScholarshipStagingUrl(import.meta.env.VITE_SUPABASE_URL)) {
    const { data: auth, error: authError } = await client.auth.getUser()
    if (authError || !auth.user) throw new Error('Authenticated administrator required.')
    const { data: allowed, error: checkError } = await client.rpc('is_admin_user', { p_user_id: auth.user.id })
    if (checkError) throw new Error('Staging administrator verification unavailable.')
    if (allowed !== true) throw new Error('Active MFA-verified staging super-administrator required. Access is not yet provisioned.')
    return { kind: 'ready', admin: {
      user: { id: auth.user.id, email: auth.user.email },
      role: { key: 'super_admin', name: 'Staging guardian reviewer' },
      permissions: ['*'],
      mfa: { currentLevel: 'aal2', nextLevel: 'aal2' },
    } }
  }
  const admin = await getAdminMe(client)
  if (admin.mfa?.currentLevel !== 'aal2') throw new Error('MFA verification is required. Please sign in again.')
  return { kind: 'ready', admin }
}
