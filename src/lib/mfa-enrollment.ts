import type { SupabaseClient } from '@supabase/supabase-js'

export type Enrollment =
  | { kind: 'verified' }
  | { kind: 'resume'; id: string }
  | { kind: 'enroll'; id: string; qr: string; secret: string }

// Share only truly concurrent requests. Never store a TOTP seed across page reloads.
// In particular, reloading the admin page MUST NOT silently replace a factor
// already present in someone's Google Authenticator app.
const pending = new WeakMap<SupabaseClient, Map<string, Promise<Enrollment>>>()

export function prepareEnrollment(client: SupabaseClient, email?: string, restartUnverified = false): Promise<Enrollment> {
  const name = email ? `MELA Central Admin - ${email}` : 'MELA Central Admin'
  let setups = pending.get(client)
  if (!setups) { setups = new Map(); pending.set(client, setups) }
  const key = `${name}:${restartUnverified ? 'restart' : 'check'}`
  const existing = setups.get(key)
  if (existing) return existing

  const operation = (async (): Promise<Enrollment> => {
    const { data: factors, error } = await client.auth.mfa.listFactors()
    if (error) throw error
    if (!factors) throw new Error('Could not check existing authenticators. Please retry.')
    // Only verified factors confer authentication assurance.
    if (factors.all.some(f => f.factor_type === 'totp' && f.status === 'verified')) return { kind: 'verified' }

    // A pending factor's original TOTP seed cannot be read back securely.
    // Never invalidate one behind the user's back or generate multiple QR seeds.
    const unfinished = factors.all.filter(f =>
      f.factor_type === 'totp' && f.status === 'unverified' && f.friendly_name === name)
    if (unfinished.length && !restartUnverified) return { kind: 'resume', id: unfinished[unfinished.length - 1].id }

    if (restartUnverified) {
      for (const factor of unfinished) {
        const { error: removeError } = await client.auth.mfa.unenroll({ factorId: factor.id })
        if (removeError) throw removeError
      }
    }

    const { data, error: enrollError } = await client.auth.mfa.enroll({
      factorType: 'totp', friendlyName: name,
    })
    if (enrollError) throw enrollError
    if (!data?.id || !data.totp?.qr_code || !data.totp.secret) {
      throw new Error('The authenticator setup was incomplete. Please retry MFA setup.')
    }
    return { kind: 'enroll', id: data.id, qr: data.totp.qr_code, secret: data.totp.secret }
  })()

  setups.set(key, operation)
  void operation.finally(() => {
    if (setups?.get(key) === operation) setups.delete(key)
  }).catch(() => {})
  return operation
}
