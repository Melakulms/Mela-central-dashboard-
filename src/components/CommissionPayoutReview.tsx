import {useEffect,useState} from 'react'
import type {FormEvent} from 'react'
import type {SupabaseClient} from '@supabase/supabase-js'
import {adminApi} from '../lib/admin-api'

type Commission = {
 id:string; inviter_user_id:string; registered_user_id:string; amount:number;
 currency:string; source_order_id:string|null; status:string; invitation_code:string|null
}
type Readiness = {payouts_enabled:boolean}
type PayoutResult = {status:string;commission_id:string}

export default function CommissionPayoutReview({client}:{client:SupabaseClient}){
 const [rows,setRows]=useState<Commission[]>([])
 const [ready,setReady]=useState(false)
 const [selected,setSelected]=useState<Commission|null>(null)
 const [provider,setProvider]=useState('')
 const [reference,setReference]=useState('')
 const [evidence,setEvidence]=useState('')
 const [sentConfirmed,setSentConfirmed]=useState(false)
 const [payeeConfirmed,setPayeeConfirmed]=useState(false)
 const [sourceConfirmed,setSourceConfirmed]=useState(false)
 const [busy,setBusy]=useState(false)
 const [error,setError]=useState('')
 const [notice,setNotice]=useState('')
 const [loaded,setLoaded]=useState(false)
 const refresh=async()=>{
   setBusy(true);setError('')
   try{
     const [listing,readiness]=await Promise.all([
       adminApi(client,'commission.list',{status:'pending',limit:100}),
       client.rpc('mela_payment_readiness_v1',{p_action:'status',p_data:{}})
     ])
     if(readiness.error)throw readiness.error
     if(!readiness.data||typeof readiness.data!=='object')throw new Error('Cannot confirm financial safety switches.')
     const read=readiness.data as Readiness
     const data=listing?.data
     if(!Array.isArray(data))throw new Error('Cannot load the authorized pending commission queue.')
     setReady(read.payouts_enabled===true)
     setRows(data.filter((v:Commission)=>v.status==='pending'))
   }catch(e){setReady(false);setRows([]);setError(e instanceof Error?e.message:'Could not read commission safety status.')}
   finally{setBusy(false);setLoaded(true)}
 }
 useEffect(()=>{void refresh()},[client])
 const reset=()=>{setSelected(null);setProvider('');setReference('');setEvidence('');
  setSentConfirmed(false);setPayeeConfirmed(false);setSourceConfirmed(false)}
 const record=async(event:FormEvent<HTMLFormElement>)=>{
  event.preventDefault()
  if(!selected||busy||!ready)return
  if(!sentConfirmed||!payeeConfirmed||!sourceConfirmed){
   setError('All three independent confirmations are required.');return
  }
  const normalizedReference=reference.trim().toUpperCase()
  if(!['telebirr','dashen','bank'].includes(provider)
    || !/^[A-Z0-9][A-Z0-9-]{5,63}$/.test(normalizedReference)
    || evidence.trim().length<20 || evidence.trim().length>500){
   setError('Provide the real outgoing payment method, 6–64 character reference and 20–500 character evidence note.')
   return
  }
  setBusy(true);setError('');setNotice('')
  try{
   const {data,error}=await client.rpc('mela_record_referral_payout_v1',{
    p_commission_id:selected.id,p_provider:provider,p_reference:normalizedReference,p_evidence_note:evidence.trim()
   })
   if(error)throw error
   const result=data as PayoutResult|null
   if(result?.status!=='paid'||result.commission_id!==selected.id)
     throw new Error('Payout recording was not confirmed. Review the ledger before any repeat.')
   const id=selected.id
   reset()
   setNotice('Outgoing commission transfer recorded. Refreshing the independently saved commission status…')
   const check=await adminApi(client,'commission.inspect',{commission_id:id})
   if(check?.data?.status!=='paid')throw new Error('The server did not confirm the paid status. Investigate before another transfer.')
   setNotice('Paid commission and its outgoing bank evidence confirmed from the server. This screen did not send money.')
   await refresh()
  }catch(e){setError(e instanceof Error?e.message:'Failed to record outgoing payment; no new transfer should be sent.')}
  finally{setBusy(false)}
 }
 return <section className="panel" aria-label="Verified referral commission payout review">
  <div className="module-head"><div><h2>Referral commission payout review</h2>
   <p>Pro 20 ETB and Premium 40 ETB are eligible only after an independently verified first subscription. This screen records an already completed outgoing transfer; it does not send money.</p>
   </div><button type="button" disabled={busy} onClick={()=>void refresh()}>Refresh commissions</button></div>
  {error&&<p className="error" role="alert">{error}</p>}
  {notice&&<p role="status">{notice}</p>}
  {!loaded&&<p role="status">Checking pending commissions and payout permissions…</p>}
  {loaded&&!ready&&<p role="status">Commission disbursements are disabled. Pending earnings can be reviewed, but no payout may be recorded until an authorized finance launch independently enables payouts.</p>}
  {loaded&&rows.length===0&&<p>No pending referral commissions in the authorized review queue.</p>}
  <div className="table-wrap"><table><thead><tr><th>Inviter</th><th>Referred customer</th><th>Verified order</th><th>Commission</th><th>Action</th></tr></thead>
  <tbody>{rows.map(row=><tr key={row.id}>
   <td>{row.inviter_user_id.slice(0,8)}…</td><td>{row.registered_user_id.slice(0,8)}…</td>
   <td>{row.source_order_id?.slice(0,8)??'Not linked'}…</td>
   <td>{row.amount} {row.currency}</td>
   <td><button type="button" disabled={busy||!ready||!row.source_order_id||row.currency!=='ETB'||![20,40].includes(Number(row.amount))}
     onClick={()=>{reset();setSelected(row);setError('');setNotice('')}}>Review outgoing evidence</button></td>
  </tr>)}</tbody></table></div>
  {selected&&ready&&<form className="detail-card" onSubmit={event=>void record(event)}>
   <h3>Record existing outgoing bank transfer</h3>
   <p>Only proceed after separately verifying the payee's MELA-registered payout account and the outgoing bank or Telebirr transaction in the actual provider account. Never initiate a new transfer merely to pass a MELA test.</p>
   <p>Commission {selected.id} — {selected.amount} {selected.currency}. Source order: {selected.source_order_id}.</p>
   <label>Outgoing method<select value={provider} onChange={e=>setProvider(e.target.value)} required>
     <option value="">Choose method</option><option value="telebirr">Telebirr</option>
     <option value="dashen">Dashen Bank</option><option value="bank">Other bank</option>
   </select></label>
   <label>Actual outgoing transfer reference<input required maxLength={64} value={reference}
     onChange={e=>setReference(e.target.value.toUpperCase())} /></label>
   <label>Private independent evidence (20–500 characters)<textarea required value={evidence}
      maxLength={500} onChange={e=>setEvidence(e.target.value)}
      placeholder="Describe what you confirmed from the provider's outgoing transaction record. Do not enter account PINs or OTPs."/></label>
   <label><input type="checkbox" checked={sentConfirmed} onChange={e=>setSentConfirmed(e.target.checked)}/> I independently confirmed the outgoing money really left the MELA payment account.</label>
   <label><input type="checkbox" checked={payeeConfirmed} onChange={e=>setPayeeConfirmed(e.target.checked)}/> I independently confirmed the recipient is the verified MELA referral payee.</label>
   <label><input type="checkbox" checked={sourceConfirmed} onChange={e=>setSourceConfirmed(e.target.checked)}/> I checked the first paid subscription, receipt and exact 20/40 ETB eligibility.</label>
   <div className="toolbar"><button type="button" disabled={busy} onClick={reset}>Cancel</button>
    <button type="submit" disabled={busy||!sentConfirmed||!payeeConfirmed||!sourceConfirmed||
        !['telebirr','dashen','bank'].includes(provider)||!/^[A-Za-z0-9][A-Za-z0-9-]{5,63}$/.test(reference.trim())||
        evidence.trim().length<20||evidence.trim().length>500}>Record verified outgoing payout</button>
   </div>
  </form>}
 </section>
}
