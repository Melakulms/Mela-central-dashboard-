import React, { useEffect, useState, useRef } from 'react'
import type { SupabaseClient } from '@supabase/supabase-js'
import { prepareEnrollment } from '../lib/mfa-enrollment'
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
  const resetPending = useRef(false)
  const [restartRequired, setRestartRequired] = useState(false)
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
      setRestartRequired(false)

      try {
        const explicitRestart = resetPending.current
        resetPending.current = false
        const enrollment = await prepareEnrollment(client, email, explicitRestart)
        if (!active) return
        if (enrollment.kind === 'verified') {
          onEnrolledRef.current()
          return
        }
        if (enrollment.kind === 'restart_required') {
          setRestartRequired(true)
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

  const beginNewSetup = () => {
    if (verifying || loading) return
    resetPending.current = true
    setRetry(value => value + 1)
  }

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
        const detail = cause instanceof Error ? cause.message : 'MFA verification failed.'
        setError(/invalid|code|expired|factor|challenge/i.test(detail)
          ? 'The code was not accepted. Use the current MELA Central Admin entry in Google Authenticator, confirm Automatic date & time is enabled on your phone, and enter a fresh six-digit code before it changes. If you scanned an earlier QR code, start a new setup below.'
          : detail)
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
      {restartRequired && <div className="notice" role="status"><strong>Unfinished authenticator setup found</strong><p>You previously started MFA enrollment, but it was not verified. For security, the original setup key cannot be displayed again. The existing Google Authenticator code might refer to that earlier setup.</p><p>To recover, start a new setup, add its current key to Google Authenticator, and verify the fresh six-digit code. Older authenticator entries will no longer work.</p><button type="button" className="secondary" onClick={beginNewSetup}>Start a new MFA setup</button></div>}
      {factorId && <><p className="muted">Add a new <strong>MELA Central Admin</strong> entry in Google Authenticator using this QR code. Do not use codes from older MELA entries.</p>
      {qr && <img src={qr} alt="MFA enrollment QR code" style={{ width: 220, maxWidth: '100%', height: 'auto', margin: '12px auto', display: 'block' }} />}
      <p className="muted">Using one Android phone? In Google Authenticator tap + → Enter a setup key, enter account name MELA Central Admin, paste the key below, and choose Time based. Do not share the key or the six-digit code.</p>
      <code style={{ display: 'block', wordBreak: 'break-all', padding: 12 }}>{secret}</code>
      <button className="secondary" type="button" disabled={verifying} onClick={() => { void navigator.clipboard?.writeText(secret).catch(() => setError('Could not copy the setup key. Select it manually.')) }}>Copy setup key</button>
      <p className="muted">Confirm Android Settings → System → Date & time → Set time automatically. Enter the current code before the timer changes.</p>
      <label>Authenticator code<input className="mfa" inputMode="numeric" autoComplete="one-time-code" maxLength={6} disabled={verifying} value={code} onChange={e => setCode(e.target.value.replace(/\D/g, ''))} /></label></>}
      {error && <div className="error" role="alert">{error}</div>}
      <button disabled={verifying || !factorId || code.length !== 6} onClick={() => void verify()}>{verifying ? 'Verifying…' : 'Enable MFA and continue'}</button>
      {factorId && <button className="secondary" type="button" disabled={verifying} onClick={beginNewSetup}>Discard this setup and start again</button>}
      {!factorId && !restartRequired && <button className="secondary" type="button" onClick={() => setRetry(value => value + 1)}>Retry MFA setup</button>}
      <button className="secondary" disabled={verifying} onClick={onCancel}>Sign out</button>
    </div>
  </div>
}
