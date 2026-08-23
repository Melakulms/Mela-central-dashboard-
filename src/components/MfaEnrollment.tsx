import React, { useEffect, useState } from 'react'
import type { SupabaseClient } from '@supabase/supabase-js'

type Props = {
  client: SupabaseClient
  email?: string
  onEnrolled: () => void
  onCancel: () => void
}

export function MfaEnrollment({ client, email, onEnrolled, onCancel }: Props) {
  const [factorId, setFactorId] = useState('')
  const [qr, setQr] = useState('')
  const [secret, setSecret] = useState('')
  const [code, setCode] = useState('')
  const [loading, setLoading] = useState(true)
  const [verifying, setVerifying] = useState(false)
  const [error, setError] = useState('')

  useEffect(() => {
    let active = true
    ;(async () => {
      setLoading(true)
      setError('')
      const { data, error: enrollError } = await client.auth.mfa.enroll({
        factorType: 'totp',
        friendlyName: email ? `MELA Central Admin - ${email}` : 'MELA Central Admin',
      })
      if (!active) return
      if (enrollError) {
        setError(enrollError.message)
        setLoading(false)
        return
      }
      setFactorId(data.id)
      setQr(data.totp.qr_code)
      setSecret(data.totp.secret)
      setLoading(false)
    })()
    return () => { active = false }
  }, [client, email])

  const verify = async () => {
    if (!factorId || !/^\d{6}$/.test(code)) return
    setVerifying(true)
    setError('')
    const { data: challenge, error: challengeError } = await client.auth.mfa.challenge({ factorId })
    if (challengeError) {
      setError(challengeError.message)
      setVerifying(false)
      return
    }
    const { error: verifyError } = await client.auth.mfa.verify({
      factorId,
      challengeId: challenge.id,
      code,
    })
    setVerifying(false)
    if (verifyError) {
      setError(verifyError.message)
      return
    }
    const { data: assurance } = await client.auth.mfa.getAuthenticatorAssuranceLevel()
    if (assurance?.currentLevel !== 'aal2') {
      setError('MFA verification completed but the session did not reach AAL2. Sign in again and retry.')
      return
    }
    onEnrolled()
  }

  if (loading) return <div className="center"><div className="card login"><h1>Setting up MFA…</h1><p className="muted">Preparing your secure authenticator enrollment.</p></div></div>

  return <div className="center">
    <div className="card login">
      <h1>Set up administrator MFA</h1>
      <p className="muted">Scan this QR code with Google Authenticator, Microsoft Authenticator, 1Password, or another TOTP authenticator.</p>
      {qr && <img src={`data:image/svg+xml;utf8,${encodeURIComponent(qr)}`} alt="MFA enrollment QR code" style={{ width: 220, height: 220, margin: '12px auto', display: 'block' }} />}
      <p className="muted">If you cannot scan it, enter this setup secret manually:</p>
      <code style={{ display: 'block', wordBreak: 'break-all', padding: 12 }}>{secret}</code>
      <label>Authenticator code<input className="mfa" inputMode="numeric" autoComplete="one-time-code" maxLength={6} value={code} onChange={e => setCode(e.target.value.replace(/\D/g, ''))} /></label>
      {error && <div className="error">{error}</div>}
      <button disabled={verifying || code.length !== 6} onClick={() => void verify()}>{verifying ? 'Verifying…' : 'Enable MFA and continue'}</button>
      <button className="secondary" onClick={onCancel}>Sign out</button>
    </div>
  </div>
}
