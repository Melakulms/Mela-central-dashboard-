import React, { useEffect, useState, useRef } from 'react'
import type { SupabaseClient } from '@supabase/supabase-js'
import { prepareEnrollment } from '../lib/prepare-enrollment'
import { verifyEnrollment } from '../lib/verify-enrollment'

type Props = {
  client: SupabaseClient
  email?: string
  onEnrolled: () => void
  onCancel: () => void
}

export function MfaEnrollment({ client, email, onEnrolled, onCancel }: Props) {
  const onEnrolledRef=useRef(onEnrolled)
  useEffect(()=>{onEnrolledRef.current=onEnrolled},[onEnrolled])
  const generation = useRef(0)
  const verificationPending = useRef(false)
  const [retry, setRetry] = useState(0)
  const [factorId, setFactorId] = useState('')
  const [qr, setQr] = useState('')
  const [secret, setSecret] = useState('')
  const [code, setCode] = useState('')
  const [loading, setLoading] = useState(true)
  const [verifying, setVerifying] = useState(false)
  const [error, setError] = useState('')

  useEffect(() => {
    let active = true
    generation.current++

    const prepare = async () => {
      setLoading(true)
      setError('')
      setFactorId('')
      setQr('')
      setSecret('')
      setCode('')

      try {
        const enrollment = await prepareEnrollment(client, email)
        if (!active) return
        if (enrollment.kind === 'verified') {
          onEnrolledRef.current()
          return
        }
        setFactorId(enrollment.id)
        setQr(enrollment.qr)
        setSecret(enrollment.secret)
      } catch (cause) {
        if (!active) return
        setError(cause instanceof Error ? cause.message : 'Unable to start MFA enrollment. Please sign in again and retry.')
      } finally {
        if (active) setLoading(false)
      }
    }

    void prepare()
    return () => {
      active = false
      generation.current++
    }
  }, [client, email, retry])

  const verify = async () => {
    if (!factorId || !/^\d{6}$/.test(code) || verificationPending.current) return
    verificationPending.current = true
    const currentGeneration = generation.current
    setVerifying(true)
    setError('')
    try {
      await verifyEnrollment(client, factorId, code)
      if (generation.current !== currentGeneration) return
      setCode(''); setSecret(''); setQr('')
      onEnrolledRef.current()
    } catch (cause) {
      if (generation.current === currentGeneration) {
        setError(cause instanceof Error ? cause.message : 'MFA verification failed. Check the code and retry.')
      }
    } finally {
      verificationPending.current = false
      if (generation.current === currentGeneration) setVerifying(false)
    }
  }

  if (loading) {
    return <div className="center"><div className="card login"><h1>Setting up MFA…</h1><p className="muted">Preparing your secure authenticator enrollment.</p></div></div>
  }

  return <div className="center">
    <div className="card login">
      <h1>Set up administrator MFA</h1>
      {factorId && <><p className="muted">Scan this QR code with Google Authenticator, Microsoft Authenticator, 1Password, or another TOTP authenticator.</p>
      {qr && <img src={qr} alt="MFA enrollment QR code" style={{ width: 220, maxWidth: '100%', height: 'auto', margin: '12px auto', display: 'block' }} />}
      <p className="muted">If you cannot scan it, enter this setup secret manually:</p>
      <code style={{ display: 'block', wordBreak: 'break-all', padding: 12 }}>{secret}</code>
      <label>Authenticator code<input className="mfa" inputMode="numeric" autoComplete="one-time-code" maxLength={6} disabled={verifying} value={code} onChange={e => setCode(e.target.value.replace(/\D/g, ''))} /></label></>}
      {error && <div className="error" role="alert">{error}</div>}
      <button disabled={verifying || !factorId || code.length !== 6} onClick={() => void verify()}>{verifying ? 'Verifying…' : 'Enable MFA and continue'}</button>
      {!factorId && <button className="secondary" onClick={() => setRetry(value => value + 1)}>Retry MFA setup</button>}
      <button className="secondary" disabled={verifying} onClick={onCancel}>Sign out</button>
    </div>
  </div>
}
