import {useEffect,useState} from 'react'
import type {SupabaseClient} from '@supabase/supabase-js'
import {verifyAdminTotp,safeTotpError} from '../lib/admin-totp'

type Factor={id:string;status:string;factor_type:string;friendly_name?:string}

/** Enroll an independent second TOTP while already signed in with AAL2.
 * Lost *all* factors: no self-service bypass. An established, independent,
 * authorized operator must use a documented out-of-band recovery process.
 */
export default function MfaBackupSetup({client}:{client:SupabaseClient}){
 const [factors,setFactors]=useState<Factor[]>([])
 const [loading,setLoading]=useState(true)
 const [busy,setBusy]=useState(false)
 const [factorId,setFactorId]=useState('')
 const [qr,setQr]=useState('')
 const [secret,setSecret]=useState('')
 const [code,setCode]=useState('')
 const [error,setError]=useState('')
 const [message,setMessage]=useState('')
 const reload=async()=>{
   const [assurance,list]=await Promise.all([
     client.auth.mfa.getAuthenticatorAssuranceLevel(),client.auth.mfa.listFactors(),
   ])
   if(assurance.error)throw assurance.error
   if(assurance.data?.currentLevel!=='aal2')throw new Error('Complete administrator MFA before managing backup authenticators.')
   if(list.error)throw list.error
   setFactors((list.data?.all??[]).filter(f=>f.factor_type==='totp') as Factor[])
 }
 useEffect(()=>{
   let active=true
   void(async()=>{
     try{await reload()}catch(e){if(active)setError(e instanceof Error?e.message:'Unable to load authenticators.')}
     finally{if(active)setLoading(false)}
   })()
   return()=>{active=false}
 },[client])
 const verified=factors.filter(f=>f.status==='verified')
 const start=async()=>{
   if(busy||factorId||verified.length>=2)return
   setBusy(true);setError('');setMessage('')
   try{
     const assurance=await client.auth.mfa.getAuthenticatorAssuranceLevel()
     if(assurance.error)throw assurance.error
     if(assurance.data?.currentLevel!=='aal2')throw new Error('Complete administrator MFA first.')
     const result=await client.auth.mfa.enroll({factorType:'totp',friendlyName:'MELA Admin backup'})
     if(result.error)throw result.error
     if(!result.data?.id||!result.data.totp?.secret)throw new Error('Backup enrollment did not return a setup key.')
     setFactorId(result.data.id)
     setQr(result.data.totp.qr_code||'')
     setSecret(result.data.totp.secret)
   }catch(e){setError(safeTotpError(e))}
   finally{setBusy(false)}
 }
 const verify=async()=>{
   if(busy||!factorId||!/^[0-9]{6}$/.test(code))return
   setBusy(true);setError('')
   try{
     await verifyAdminTotp(client,factorId,code)
     setSecret('');setQr('');setFactorId('');setCode('')
     await reload()
     setMessage('Backup authenticator verified. Keep it on a separate device or in a secured authenticator account.')
   }catch(e){setError(safeTotpError(e))}
   finally{setBusy(false)}
 }
 const cancel=async()=>{
   if(busy||!factorId)return
   setBusy(true);setError('')
   try{
     const r=await client.auth.mfa.unenroll({factorId})
     if(r.error)throw r.error
     setFactorId('');setQr('');setSecret('');setCode('')
     await reload()
   }catch(e){setError(safeTotpError(e))}
   finally{setBusy(false)}
 }
 return <section className="panel" aria-label="Administrator MFA backup">
  <div className="module-head"><div><h2>MFA backup & recovery readiness</h2>
   <p>Register a second authenticator while your primary one still works. Administrative access always requires a verified code.</p>
  </div></div>
  {loading?<p role="status">Checking MFA factors…</p>:<>
   <p role="status">{verified.length} verified authenticator{verified.length===1?'':'s'}. {verified.length<2?'Backup protection is not yet complete.':'Backup factor available.'}</p>
   <ul>{verified.map((f,index)=><li key={f.id}>{f.friendly_name||`Authenticator ${index+1}`} — verified</li>)}</ul>
   {verified.length<2&&!factorId&&<button type="button" disabled={busy} onClick={()=>void start()}>Add backup authenticator</button>}
   {factorId&&<div className="detail-card">
    <p><strong>New backup setup:</strong> Add the following key to a DIFFERENT authenticator/device from your primary one. On one Android phone you may copy the setup key into another trusted authenticator, but that does not protect against losing the phone.</p>
    {qr&&<img src={qr} alt="Backup authenticator QR code" style={{maxWidth:220,width:'100%',display:'block',margin:'12px auto'}}/>}
    <code style={{display:'block',wordBreak:'break-all',padding:12}}>{secret}</code>
    <label>Current six-digit code from NEW backup entry<input aria-label="Backup authenticator code" value={code}
      maxLength={6} inputMode="numeric" autoComplete="one-time-code" disabled={busy}
      onChange={event=>setCode(event.target.value.replace(/\D/g,''))}/></label>
    <button type="button" disabled={busy||code.length!==6} onClick={()=>void verify()}>Verify backup code</button>
    <button type="button" disabled={busy} onClick={()=>void cancel()}>Discard unfinished backup</button>
   </div>}
   <p><strong>If all authenticators are lost:</strong> Sign-in must remain blocked. Use an independently verified support process with another MFA-authenticated super administrator. Never send a six-digit code, setup key, password or recovery secret to support over chat. MELA cannot automatically bypass MFA from this page.</p>
  </>}
  {message&&<p role="status">{message}</p>}
  {error&&<div className="error" role="alert">{error}</div>}
 </section>
}
