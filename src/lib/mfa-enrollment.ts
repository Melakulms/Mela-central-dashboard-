import type { SupabaseClient } from '@supabase/supabase-js'

export type TotpEnrollmentPreparation =
  | { kind: 'verified'; factorId: string }
  | { kind: 'new'; factorId: string; qrCode: string; secret: string }

export async function prepareTotpEnrollment(client: SupabaseClient): Promise<TotpEnrollmentPreparation> {
  const { data: factors, error: factorsError } = await client.auth.mfa.listFactors()
  if (factorsError) throw factorsError
  if (!factors) throw new Error('Could not check existing authenticators. Please retry.')

  const verified = factors.totp.find(factor => factor.status === 'verified')
  if (verified) return { kind: 'verified', factorId: verified.id }

  for (const factor of factors.totp.filter(factor => factor.status !== 'verified')) {
    const { error: unenrollError } = await client.auth.mfa.unenroll({ factorId: factor.id })
    if (unenrollError) throw unenrollError
  }

  // A friendly name is optional in Supabase. Leaving it unset avoids
  // mfa_factor_name_conflict when a stale server-side enrollment with the
  // previous display name survives a failed setup attempt.
  const { data, error: enrollError } = await client.auth.mfa.enroll({ factorType: 'totp' })
  if (enrollError) throw enrollError

  return {
    kind: 'new',
    factorId: data.id,
    qrCode: data.totp.qr_code,
    secret: data.totp.secret,
  }
}
