import {useEffect,useState} from 'react'
import type {SupabaseClient} from '@supabase/supabase-js'

type Receiver={id:string;provider:string;recipient:string;label:string;active:boolean;verified:boolean}
type Product={title:string;amount_minor:number;active:boolean;product_key:string}
type Readiness={checkout_enabled:boolean;platform_payments_enabled:boolean;payouts_enabled:boolean;active_reviewers:number;paid_products:Product[];accounts:Receiver[]}
export default function PaymentReadinessPanel({client}:{client:SupabaseClient}){
 const [data,setData]=useState<Readiness|null>(null)
 const [selected,setSelected]=useState<Receiver|null>(null)
 const [note,setNote]=useState('')
 const [control,setControl]=useState(false)
 const [owner,setOwner]=useState(false)
 const [recipientConfirmed,setRecipientConfirmed]=useState(false)
 const [busy,setBusy]=useState(false)
 const [error,setError]=useState('')
 const [notice,setNotice]=useState('')
 async function load(){
  setBusy(true);setError('')
  try{
    const {data:response,error}=await client.rpc('mela_payment_readiness_v1',{p_action:'status',p_data:{}})
    if(error)throw error
    if(!response||!Array.isArray(response.accounts)||!Array.isArray(response.paid_products))throw new Error('Invalid financial readiness response')
    setData(response as Readiness)
  }catch(e){setData(null);setError(e instanceof Error?e.message:'Financial setup is unavailable. MFA may be required.')}
  finally{setBusy(false)}
 }
 useEffect(()=>{void load()},[client])
 const choose=(a:Receiver)=>{setSelected(a);setNote('');setControl(false);setOwner(false);setRecipientConfirmed(false);setError('');setNotice('')}
 const send=async(action:'verify_account'|'deactivate_account')=>{
   if(!selected||busy)return
   setBusy(true);setError('');setNotice('')
   try{
    const payload:Record<string,unknown>={account_id:selected.id}
    if(action==='verify_account'){
      if(!control||!owner||!recipientConfirmed||note.trim().length<40)throw new Error('Confirm actual account ownership, access and recipient; provide 40+ characters of evidence.')
      payload.confirmed_control=control
      payload.confirmed_account_owner=owner
      payload.confirmed_correct_recipient=recipientConfirmed
      payload.evidence_note=note.trim()
    }
    const {data:result,error}=await client.rpc('mela_payment_readiness_v1',{p_action:action,p_data:payload})
    if(error)throw error
    if(result?.status!==(action==='verify_account'?'verified':'deactivated'))throw new Error('The bank account status was not confirmed.')
    // Do not report verified until an independent server read confirms the write.
    const {data:fresh,error:refreshError}=await client.rpc('mela_payment_readiness_v1',{p_action:'status',p_data:{}})
    if(refreshError)throw new Error('The submission returned, but its saved status could not be confirmed. Refresh to check the account.')
    if(!fresh || !Array.isArray(fresh.accounts))throw new Error('Could not read the bank account status from MELA.')
    const saved=(fresh as Readiness).accounts.find(a=>a.id===selected.id)
    const persisted=action==='verify_account'
      ? saved?.active===true && saved?.verified===true
      : saved?.active===false && saved?.verified===false
    if(!persisted)throw new Error('The verification was not recorded. Check the admin MFA session and try again.')
    setData(fresh as Readiness)
    setSelected(null)
    setNotice(action==='verify_account'
      ? 'Verified and active — confirmed from MELA production records. Checkout remains separately disabled.'
      : 'Deactivation confirmed from MELA production records.')
   }catch(e){setError(e instanceof Error?e.message:'Could not update the account. No checkout setting changed.')}
   finally{setBusy(false)}
 }
 return <section className="panel" aria-label="Subscription payment readiness and receiving account verification">
   <div className="module-head"><div><h2>Subscription payment readiness</h2><p>Owner-only account verification requires an active MFA session and payment reviewer permission. Marking a receiving account verified does not enable payment collection.</p></div>
    <button type="button" disabled={busy} onClick={()=>void load()}>Refresh readiness</button></div>
   {error&&<p className="error" role="alert">{error}</p>}
   {notice&&<p role="status">{notice}</p>}
   {!data&&<p>{busy?'Loading payment setup…':'Payment setup is not available.'}</p>}
   {data&&<>
     <p><strong>Subscription checkout:</strong> {data.checkout_enabled?'Enabled':'Disabled — no subscription transfers should be requested'}</p>
     <p><strong>Platform payment flag:</strong> {data.platform_payments_enabled?'Enabled':'Disabled'} · <strong>Commission payouts:</strong> {data.payouts_enabled?'Enabled':'Disabled'} · <strong>Active payment reviewers:</strong> {data.active_reviewers}</p>
     <h3>Configured plans</h3>
     <ul>{data.paid_products.map(p=><li key={p.product_key}>{p.title} — {(p.amount_minor/100).toFixed(0)} ETB · {p.active?'Available':'Not available for checkout'}</li>)}</ul>
     <h3>Receiving accounts</h3>
     {!data.accounts.length&&<p>No configured receiving accounts found.</p>}
     <div className="table-wrap"><table><thead><tr><th>Provider</th><th>Receiving account</th><th>Verification</th><th>Action</th></tr></thead>
       <tbody>{data.accounts.map(a=><tr key={a.id}><td>{a.provider}</td><td>{a.label}<small>{a.recipient}</small></td>
         <td>{a.verified&&a.active?'Verified and active':'Not verified for new orders'}</td>
         <td><button type="button" disabled={busy} onClick={()=>choose(a)}>{a.active?'Review / deactivate':'Verify ownership'}</button></td>
       </tr>)}</tbody></table></div>
     <p className="muted">A bank statement or verified banking-app account details must confirm the real owner and exact receiving number. No screenshots or unverified transfer claims are proof of ownership. Payment collection and payouts remain separately disabled until a full finance launch review.</p>
   </>}
   {selected&&<div className="detail-card" aria-label="Receiving account confirmation">
      <h3>Verify {selected.provider} receiving account</h3>
      <p><strong>{selected.label} — {selected.recipient}</strong></p>
      <p>Only confirm after checking the institution’s actual account details in your own banking application or statement.</p>
      <label><input type="checkbox" checked={control} onChange={e=>setControl(e.target.checked)} /> I verified live access to this receiving account.</label>
      <label><input type="checkbox" checked={owner} onChange={e=>setOwner(e.target.checked)} /> I confirmed the holder is authorized to receive MELA payments.</label>
      <label><input type="checkbox" checked={recipientConfirmed} onChange={e=>setRecipientConfirmed(e.target.checked)} /> I checked this exact recipient number independently.</label>
      <label>Private verification evidence note<textarea value={note} onChange={e=>setNote(e.target.value)} maxLength={500} placeholder="Describe the bank statement/account information you independently verified; do not enter a password or PIN." /></label>
      <div className="toolbar">
        <button type="button" disabled={busy} onClick={()=>setSelected(null)}>Cancel</button>
        {selected.active&&<button type="button" disabled={busy} onClick={()=>void send('deactivate_account')}>Deactivate receiver</button>}
        <button type="button" disabled={busy||!control||!owner||!recipientConfirmed||note.trim().length<40} onClick={()=>void send('verify_account')}>Record MFA-verified ownership</button>
      </div>
   </div>}
 </section>
}
