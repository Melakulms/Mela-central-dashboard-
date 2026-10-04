import type { SupabaseClient } from '@supabase/supabase-js'

/** Complete enrollment only after refresh and assurance checks both succeed. */
export async function verifyEnrollment(client: SupabaseClient, factorId: string, code: string) {
  if (!factorId || !/^\d{6}$/.test(code)) throw new Error('Enter the six-digit authenticator code.')
  const { data: challenge, error: challengeError } = await client.auth.mfa.challenge({ factorId })
  if (challengeError) throw challengeError
  if (!challenge?.id) throw new Error('Could not start MFA verification. Please retry.')
  const { error: verifyError } = await client.auth.mfa.verify({ factorId, challengeId: challenge.id, code })
  if (verifyError) throw verifyError
  const { data: refreshed, error: refreshError } = await client.auth.refreshSession()
  if (refreshError) throw refreshError
  if (!refreshed?.session) throw new Error('Your session expired. Sign in again to continue.')
  const { data: assurance, error: assuranceError } = await client.auth.mfa.getAuthenticatorAssuranceLevel()
  if (assuranceError) throw assuranceError
  if (assurance?.currentLevel !== 'aal2' || assurance.nextLevel !== 'aal2') {
    throw new Error('MFA assurance could not be confirmed. Sign out and sign in again.')
  }
}
