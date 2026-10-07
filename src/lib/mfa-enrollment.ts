import type { SupabaseClient } from '@supabase/supabase-js'

export type Enrollment = { kind: 'verified' } | { kind: 'enroll'; id: string; qr: string; secret: string }
// Share an in-flight setup across React remounts; never persist QR codes or secrets.
const pending = new WeakMap<SupabaseClient, Map<string, Promise<Enrollment>>>()

export function prepareEnrollment(client: SupabaseClient, email?: string): Promise<Enrollment> {
  const name = email ? `MELA Central Admin - ${email}` : 'MELA Central Admin'
  let setups = pending.get(client)
  if (!setups) { setups = new Map(); pending.set(client, setups) }
  const existing = setups.get(name)
  if (existing) return existing
  const operation = (async (): Promise<Enrollment> => {
    const { data: factors, error } = await client.auth.mfa.listFactors()
    if (error) throw error
    if (!factors) throw new Error('Could not check existing authenticators. Please retry.')
    // listFactors().totp contains VERIFIED factors only; unfinished factors are in all.
    if (factors.all.some(f => f.factor_type === 'totp' && f.status === 'verified')) return { kind: 'verified' }
    for (const factor of factors.all) {
      if (factor.factor_type !== 'totp' || factor.status !== 'unverified' || factor.friendly_name !== name) continue
      const { error: removeError } = await client.auth.mfa.unenroll({ factorId: factor.id })
      if (removeError) throw removeError
    }
    const { data, error: enrollError } = await client.auth.mfa.enroll({ factorType: 'totp', friendlyName: name })
    if (enrollError) throw enrollError
    if (!data?.id || !data.totp?.qr_code || !data.totp.secret) throw new Error('The authenticator setup was incomplete. Please retry MFA setup.')
    return { kind: 'enroll', id: data.id, qr: data.totp.qr_code, secret: data.totp.secret }
 })()
 setups.set(name, operation)
 void operation.finally(() => { if (setups?.get(name) === operation) setups.delete(name) }).catch(() => {})
 return operation
}
