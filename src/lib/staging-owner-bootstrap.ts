import type { SupabaseClient } from '@supabase/supabase-js'

export const STAGING_OWNER_EMAIL = 'melakuanteneh1@gmail.com'

/** Only the designated, verified staging owner can request the pre-existing
 * one-time bootstrap. The database independently checks real identity, AAL2,
 * single use and records an audit row; the UI never assigns any role. */
export async function claimStagingOwnerAdmin(client: SupabaseClient): Promise<void> {
  const { data: auth, error: authError } = await client.auth.getUser()
  if (authError) throw authError
  if (!auth.user || auth.user.email?.trim().toLowerCase() !== STAGING_OWNER_EMAIL) {
    throw new Error('Only the designated staging owner may request first administrator setup.')
  }
  if (!auth.user.email_confirmed_at) {
    throw new Error('Confirm your owner email before administrator setup.')
  }
  const { data: assurance, error: assuranceError } = await client.auth.mfa.getAuthenticatorAssuranceLevel()
  if (assuranceError) throw assuranceError
  if (assurance?.currentLevel !== 'aal2') {
    throw new Error('Verify Google Authenticator before claiming administrator access.')
  }
  const { data, error } = await client.rpc('claim_staging_first_super_admin')
  if (error) throw error
  if (!data || data.success !== true) {
    const code = typeof data?.code === 'string' ? data.code : 'bootstrap_denied'
    throw new Error('Administrator setup was not completed (' + code + ').')
  }
}
