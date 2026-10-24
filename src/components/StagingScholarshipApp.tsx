import { useCallback, useEffect, useState } from 'react'
import { ShieldCheck } from 'lucide-react'
import type { Session, SupabaseClient } from '@supabase/supabase-js'
import { MfaEnrollment } from './MfaEnrollment'
import GuardianVerificationPanel from './GuardianVerificationPanel'
import ScholarshipResearchReviewPanel from './ScholarshipResearchReviewPanel'
import { isScholarshipStagingUrl } from '../lib/scholarship-staging'

type Gate = 'loading' | 'login' | 'mfa-enroll' | 'mfa-challenge' | 'authorized' | 'blocked'
type Connection = 'checking' | 'online' | 'unavailable'
const ISSUE = 'This is an isolated staging administrator preview. It never grants administrator privileges automatically.'

function humanError(reason: unknown): string {
  const message = reason instanceof Error ? reason.message : String(reason ?? '')
  if (/failed to fetch|networkerror|fetch failed|load failed|network request failed|ERR_NAME_NOT_RESOLVED|ERR_INTERNET_DISCONNECTED/i.test(message)) {
    return 'Could not reach MELA staging authentication. Check your internet connection, open this link in Chrome, and retry the connection test. No account changes were made.'
  }
  if (/invalid login credentials|invalid email or password/i.test(message)) return 'The staging email/password was not accepted. Staging is separate from the live MELA database.'
  return message.slice(0, 320) || 'Could not verify the staging request.'
}

/** Guardian and source-review staging console. No payment reviewer role or production admin API. */
export default function StagingScholarshipApp({ client }: { client: SupabaseClient }) {
  const staging = isScholarshipStagingUrl(import.meta.env.VITE_SUPABASE_URL)
  const [gate,setGate] = useState<Gate>('loading')
  const [session,setSession] = useState<Session|null>(null)
  const [email,setEmail] = useState('')
  const [password,setPassword] = useState('')
  const [factorId,setFactorId] = useState('')
  const [code,setCode] = useState('')
  const [busy,setBusy] = useState(false)
  const [error,setError] = useState('')
  const [connection,setConnection] = useState<Connection>('checking')
  const [connectionDetail,setConnectionDetail] = useState('')
  const [revision,setRevision] = useState(0)

  const diagnose = useCallback(async () => {
    setConnection('checking'); setConnectionDetail('')
    if (!staging) { setConnection('unavailable');setConnectionDetail('Incorrect backend target. This admin preview must use MELA staging only.');return }
    try {
      const { error: testError } = await client.from('universities')
        .select('id', { count:'exact',head:true })
      if (testError) throw testError
      setConnection('online')
    } catch (cause) {
      setConnection('unavailable')
      setConnectionDetail(humanError(cause))
    }
  },[client,staging])

  const check = useCallback(async (current: Session|null) => {
    if (!current) {setGate('login');return}
    setGate('loading');setError('')
    try {
      const {data: identity,error: identityError}=await client.auth.getUser()
      if (identityError) throw identityError
      if (!identity.user || identity.user.id!==current.user.id) throw new Error('The staging Auth session is not valid. Sign in again.')
      // The assignment check is read-only. It verifies existing super-admin registration
      // BEFORE offering MFA enrollment to avoid enrolling a normal student as a reviewer.
      const {data: assigned,error: assignmentError}=await client.rpc('staging_super_admin_assignment_v1')
      if (assignmentError) throw assignmentError
      if (assigned!==true) throw new Error('No active staging super-administrator assignment exists for this account. Scholarship/guardian reviews are unavailable until one is securely provisioned.')
      const {data: aal,error: aalError}=await client.auth.mfa.getAuthenticatorAssuranceLevel()
      if (aalError) throw aalError
      if (aal?.currentLevel!=='aal2') {
        const {data: factors,error: factorError}=await client.auth.mfa.listFactors()
        if (factorError) throw factorError
        const verified=factors.totp.find(f=>f.status==='verified')
        if (verified) {setFactorId(verified.id);setCode('');setGate('mfa-challenge')}
        else setGate('mfa-enroll')
        return
      }
      const {data: permitted,error: adminError}=await client.rpc('is_admin_user',{p_user_id:identity.user.id})
      if (adminError) throw adminError
      if (permitted!==true) throw new Error('Staging administrator authorization could not be confirmed. No privileged action was enabled.')
      setGate('authorized')
    } catch (cause) {
      setError(humanError(cause));setGate('blocked')
    }
  },[client])

  useEffect(()=>{
    if (!staging) return
    let live=true
    void diagnose()
    void client.auth.getSession().then(({data,error:sessionError})=>{
      if(!live)return
      if(sessionError){setError(humanError(sessionError));setGate('blocked');return}
      setSession(data.session)
      void check(data.session)
    }).catch(cause=>{
      if(live){setError(humanError(cause));setGate('blocked')}
    })
    return()=>{live=false}
  },[client,staging,check,diagnose,revision])

  const signIn=async(e:React.FormEvent)=>{
    e.preventDefault()
    if(busy||!staging)return
    setBusy(true);setError('')
    try {
      const {data,error:authError}=await client.auth.signInWithPassword({email:email.trim(),password})
      if(authError)throw authError
      setPassword('');setSession(data.session)
      await check(data.session)
    } catch(cause){setError(humanError(cause))}
    finally{setBusy(false)}
  }
  const verify=async()=>{
    if(busy||!factorId||!/^\d{6}$/.test(code))return
    setBusy(true);setError('')
    try {
      const {error:totpError}=await client.auth.mfa.challengeAndVerify({factorId,code})
      if(totpError)throw totpError
      setCode('')
      const {data,error:sessionError}=await client.auth.getSession()
      if(sessionError)throw sessionError
      setSession(data.session);await check(data.session)
    } catch(cause) {setError(humanError(cause));setCode('')}
    finally {setBusy(false)}
  }
  const signOut=async()=>{
    setBusy(true)
    try {await client.auth.signOut({scope:'local'})}
    catch { /* Staging session remains blocked without a valid server session. */ }
    finally {
      setBusy(false);setSession(null);setPassword('');setEmail('');setCode('');setError('');setGate('login')
    }
  }
  const diagnostic=<div className="notice" role="status">
    <strong>Staging connection: {connection==='online'?'Database responding':connection==='checking'?'Checking…':'Connection unavailable'}</strong>
    {connectionDetail&&<p>{connectionDetail}</p>}
    <p className="muted">Staging and production use separate accounts. This page cannot enable payment collection.</p>
    <button className="secondary" type="button" onClick={()=>void diagnose()} disabled={connection==='checking'}>Check connection again</button>
  </div>
  if(!staging)return <div className="center"><div className="card" role="alert"><h1>Staging configuration unavailable</h1><p>This page is restricted to MELA staging. Production has not been used.</p></div></div>
  if(gate==='loading')return <div className="center"><div className="card"><h1>Checking staging administration</h1>{diagnostic}</div></div>
  if(gate==='login')return <div className="center"><form className="card login" onSubmit={e=>void signIn(e)}>
    <div className="brand"><ShieldCheck size={32}/><div><strong>MELA</strong><span>Staging Guardian &amp; Scholarships</span></div></div>
    <h1>Staging administrator sign-in</h1>
    <p className="muted">{ISSUE} Existing super-administrator assignment and Authenticator MFA are required.</p>
    {diagnostic}
    <label>Email<input type="email" autoComplete="username" required value={email} onChange={e=>setEmail(e.target.value)}/></label>
    <label>Password<input type="password" autoComplete="current-password" required value={password} onChange={e=>setPassword(e.target.value)}/></label>
    {error&&<div className="error" role="alert">{error}</div>}
    <button type="submit" disabled={busy||connection==='unavailable'}>{busy?'Signing in…':'Sign in to staging'}</button>
    <small>Only assigned staging administrators can proceed. No registration or payment setup is offered here.</small>
  </form></div>
  if(gate==='blocked')return <div className="center"><div className="card blocked">
    <h1>Administrator access not available</h1>{diagnostic}
    {error&&<div className="error" role="alert">{error}</div>}
    <button onClick={()=>void check(session)} disabled={busy}>Retry access check</button>
    <button className="secondary" onClick={()=>void signOut()} disabled={busy}>Sign out</button>
  </div></div>
  if(gate==='mfa-enroll')return <MfaEnrollment client={client} email={session?.user.email}
     onEnrolled={()=>void client.auth.getSession().then(({data})=>check(data.session))}
     onCancel={()=>void signOut()}/>
  if(gate==='mfa-challenge')return <div className="center"><div className="card login">
    <h1>Verify staging administrator MFA</h1>
    <p>Enter the current six-digit code from the authenticator assigned to this staging account. Never send codes in chat.</p>
    <label>Authenticator code<input className="mfa" inputMode="numeric" autoComplete="one-time-code" maxLength={6} disabled={busy}
      value={code} onChange={e=>setCode(e.target.value.replace(/\D/g,''))}/></label>
    {error&&<div className="error" role="alert">{error}</div>}
    <button disabled={busy||code.length!==6} onClick={()=>void verify()}>{busy?'Verifying…':'Verify MFA'}</button>
    <button className="secondary" disabled={busy} onClick={()=>void signOut()}>Sign out</button>
  </div></div>
  return <div className="staging-scholarship-shell">
    <header className="staging-scholarship-header"><div className="brand"><ShieldCheck/><div><strong>MELA</strong><span>Guardian &amp; Scholarship Review · STAGING</span></div></div>
    <button onClick={()=>void signOut()} disabled={busy}>Sign out</button></header>
    <main>
      <p className="notice">Authorized super-administrator · MFA verified. Scholarship research approval does not activate payments or automatically publish university awards.</p>
      <GuardianVerificationPanel client={client}/>
      <ScholarshipResearchReviewPanel client={client}/>
    </main>
  </div>
}