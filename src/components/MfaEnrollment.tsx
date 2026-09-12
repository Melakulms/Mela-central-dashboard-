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

    const prepareEnrollment = async () => {
      setLoading(true)
      setError('')
      setFactorId('')
      setQr('')
      setSecret('')
      setCode('')

      try {
        // Do not create another factor when an already-verified admin factor exists.
        // If a previous enrollment was abandoned, remove only unverified TOTP factors
        // before starting a fresh enrollment. Supabase enroll() creates a new factor.
        const { data: factors, error: factorsError } = await client.auth.mfa.listFactors()
        if (factorsError) throw factorsError

        const verifiedTotp = factors?.totp?.find((factor) => factor.status === 'verified')
        if (verifiedTotp) {
          throw new Error('Administrator MFA is already configured. Sign out and complete the MFA verification step instead of enrolling another factor.')
        }

        const unverifiedTotp = factors?.totp?.filter((factor) => factor.status !== 'verified') ?? []
        for (const factor of unverifiedTotp) {
          const { error: unenrollError } = await client.auth.mfa.unenroll({ factorId: factor.id })
          if (unenrollError) throw unenrollError
        }

        const { data, error: enrollError } = await client.auth.mfa.enroll({
          factorType: 'totp',
          friendlyName: email ? `MELA Central Admin - ${email}` : 'MELA Central Admin',
        })
        if (enrollError) throw enrollError
        if (!active) return

        setFactorId(data.id)
        setQr(data.totp.qr_code)
        setSecret(data.totp.secret)
      } catch (cause) {
        if (!active) return
        setError(cause instanceof Error ? cause.message : 'Unable to start MFA enrollment. Please sign in again and retry.')
      } finally {
        if (active) setLoading(false)
      }
    }

    void prepareEnrollment()
    return () => {
      active = false
    }
  }, [client, email])

  const verify = async () => {
    if (!factorId || !/^\d{6}$/.test(code)) return

    setVerifying(true)
    setError('')

    try {
      const { data: challenge, error: challengeError } = await client.auth.mfa.challenge({ factorId })
      if (challengeError) throw challengeError

      const { error: verifyError } = await client.auth.mfa.verify({
        factorId,
        challengeId: challenge.id,
        code,
      })
      if (verifyError) throw verifyError

      // Force the client to obtain the new AAL2 JWT before continuing to the admin board.
      await client.auth.refreshSession()
      const { data: assurance, error: assuranceError } = await client.auth.mfa.getAuthenticatorAssuranceLevel()
      if (assuranceError) throw assuranceError

      if (assurance?.currentLevel !== 'aal2' || assurance.nextLevel !== 'aal2') {
        throw new Error('MFA verification succeeded but the session is not at AAL2. Sign out, sign in again, and retry.')
      }

      onEnrolled()
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'MFA verification failed. Check the 6-digit code and try again.')
    } finally {
      setVerifying(false)
    }
  }

  if (loading) {
    return <div className="center"><div className="card login"><h1>Setting up MFA…</h1><p className="muted">Preparing your secure authenticator enrollment.</p></div></div>
  }

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
