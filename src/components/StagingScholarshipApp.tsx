import { useCallback, useEffect, useMemo, useState } from 'react'
import { ShieldCheck } from 'lucide-react'
import type { Session, SupabaseClient } from '@supabase/supabase-js'
import ScholarshipAccessPanel from './ScholarshipAccessPanel'
import { MfaEnrollment } from './MfaEnrollment'
import { isScholarshipStagingUrl } from '../lib/scholarship-staging'

type Gate = 'loading' | 'login' | 'mfa-enroll' | 'mfa-challenge' | 'authorized' | 'blocked'

/** Completely separate staging reviewer session. No production Admin Edge API required. */
export default function StagingScholarshipApp({ client }: { client: SupabaseClient }) {
  const [gate, setGate] = useState<Gate>('loading')
  const [session, setSession] = useState<Session | null>(null)
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [factorId, setFactorId] = useState('')
  const [code, setCode] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const allowedUrl = isScholarshipStagingUrl(import.meta.env.VITE_SUPABASE_URL)
  const staging = useMemo(() => allowedUrl, [allowedUrl])

  const check = useCallback(async (current: Session | null) => {
    if (!staging || !current) { setGate('login'); return }
    setGate('loading'); setError('')
    try {
      // Read the signed-in identity and MFA level from the Auth service, not UI claims.
      const { data: identified, error: identityError } = await client.auth.getUser()
      if (identityError || !identified.user || identified.user.id !== current.user.id) {
        throw new Error('The staging Auth session could not be verified.')
      }
      const { data: aal, error: aalError } = await client.auth.mfa.getAuthenticatorAssuranceLevel()
      if (aalError || !aal) throw aalError || new Error('Unable to verify MFA level.')
      if (aal.currentLevel !== 'aal2') {
        const { data: factors, error: factorsError } = await client.auth.mfa.listFactors()
        if (factorsError) throw factorsError
        const verified = factors?.totp?.find(factor => factor.status === 'verified')
        if (!verified) { setGate('mfa-enroll'); return }
        setFactorId(verified.id); setCode(''); setGate('mfa-challenge'); return
      }
      // This RPC authorizes only active payment reviewers with aal2.
      const { error: permissionError } = await client.rpc('admin_learning_grant_query_v1', {
        p_search: '', p_learner: null,
      })
      if (permissionError) throw permissionError
      setGate('authorized')
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Unable to verify staging reviewer authorization.')
      setGate('blocked')
    }
  }, [client, staging])

  useEffect(() => {
    if (!staging) return
    let active = true
    void client.auth.getSession().then(({ data, error: failure }) => {
      if (!active) return
      if (failure) { setError(failure.message); setGate('blocked') }
      else { setSession(data.session); void check(data.session) }
    }).catch(() => { if (active) { setError('Staging Auth is unavailable.'); setGate('blocked') } })
    return () => { active = false }
  }, [client, check, staging])

  const signIn = async (e: React.FormEvent) => {
    e.preventDefault(); if (busy || !staging) return
    setBusy(true); setError('')
    try {
      const { data, error: failure } = await client.auth.signInWithPassword({ email: email.trim(), password })
      if (failure) throw failure
      setPassword('')
      setSession(data.session)
      await check(data.session)
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Staging login failed.')
    } finally { setBusy(false) }
  }
  const verify = async () => {
    if (busy || !/^\d{6}$/.test(code) || !factorId) return
    setBusy(true); setError('')
    try {
      const { error: failure } = await client.auth.mfa.challengeAndVerify({ factorId, code })
      if (failure) throw failure
      setCode('')
      const { data } = await client.auth.getSession()
      setSession(data.session)
      await check(data.session)
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'MFA verification failed.')
      setCode('')
    } finally { setBusy(false) }
  }
  const signOut = async () => {
    setBusy(true)
    try { await client.auth.signOut({ scope: 'local' }) }
    finally { setSession(null); setGate('login'); setEmail(''); setPassword(''); setCode(''); setError(''); setBusy(false) }
  }
  if (!staging) return <div role="alert" className="center"><div className="card"><h1>Staging only</h1><p>Staging scholarship administration cannot connect to another Supabase environment.</p></div></div>
  if (gate === 'loading') return <div className="center" role="status"><div className="card"><h2>Checking staging access…</h2></div></div>
  if (gate === 'login') return <div className="center"><form className="card login" onSubmit={e => void signIn(e)}>
    <div className="brand"><ShieldCheck size={32}/><div><strong>MELA</strong><span>Staging Scholarship Admin</span></div></div>
    <h1>Staging reviewer sign-in</h1><p className="muted">Test accounts only. An active payment reviewer and MFA are required. Payment collection is OFF.</p>
    <label>Email<input type="email" autoComplete="username" value={email} required onChange={e=>setEmail(e.target.value)}/></label>
    <label>Password<input type="password" autoComplete="current-password" value={password} required onChange={e=>setPassword(e.target.value)}/></label>
    {error && <div className="error" role="alert">{error}</div>}
    <button type="submit" disabled={busy}>{busy?'Checking…':'Sign in to staging'}</button>
    <small>No registration, payment or production administrator access is available on this page.</small>
  </form></div>
  if (gate === 'mfa-enroll') return <MfaEnrollment client={client} email={session?.user.email}
    onEnrolled={() => { void client.auth.getSession().then(({ data }) => check(data.session)) }}
    onCancel={() => void signOut()} />
  if (gate === 'mfa-challenge') return <div className="center"><div className="card login">
    <h1>Verify staging reviewer MFA</h1>
    <p className="muted">Enter the current code from the authenticator already enrolled for this test account. Do not share the code.</p>
    <label>Authenticator code<input className="mfa" inputMode="numeric" autoComplete="one-time-code" maxLength={6}
      value={code} disabled={busy} onChange={e=>setCode(e.target.value.replace(/\D/g,''))}/></label>
    {error && <div className="error" role="alert">{error}</div>}
    <button disabled={busy || code.length!==6} onClick={() => void verify()}>{busy?'Verifying…':'Verify MFA'}</button>
    <button className="secondary" onClick={() => void signOut()}>Sign out</button>
  </div></div>
  if (gate === 'blocked') return <div className="center"><div className="card blocked">
    <h1>Scholarship access blocked</h1>
    <p>Only assigned staging payment reviewers with verified MFA may use this console.</p>
    {error && <div className="error" role="alert">{error}</div>}
    <button onClick={() => void check(session)}>Retry access check</button>
    <button onClick={() => void signOut()}>Sign out</button>
  </div></div>
  return <div className="staging-scholarship-shell">
    <header className="staging-scholarship-header"><div className="brand"><ShieldCheck/><div>
      <strong>MELA</strong><span>Scholarship Review · STAGING</span>
    </div></div><button onClick={() => void signOut()} disabled={busy}>Sign out</button></header>
    <main><ScholarshipAccessPanel client={client}/></main>
  </div>
}
