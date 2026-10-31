import React,{useEffect,useState} from 'react'
import type {SupabaseClient} from '@supabase/supabase-js'
import {ShieldCheck,RefreshCw,AlertTriangle} from 'lucide-react'
type Order = { id:string;user_id:string;plan_key:string;amount_minor:number;currency:string;method_code:string;recipient:string;claimed_reference:string|null;status:string;created_at:string;review_note?:string|null }
export default function VerifiedBillingPanel({client}:{client:SupabaseClient}) {
 const [orders,setOrders]=useState<Order[]>([]),[selected,setSelected]=useState<Order|null>(null)
 const [busy,setBusy]=useState(false),[error,setError]=useState(''),[notice,setNotice]=useState('')
 const [bankRef,setBankRef]=useState(''),[bankAmount,setBankAmount]=useState('')
 const [recipient,setRecipient]=useState(''),[note,setNote]=useState('')
 const [received,setReceived]=useState(false),[payer,setPayer]=useState(false)
 const load=async()=>{setBusy(true);setError('');try{
   const {data,error:problem}=await client.rpc('mela_billing_admin_list_v1')
   if(problem)throw problem
   setOrders(Array.isArray(data)?data as Order[]:[])
 }catch(e){setError(e instanceof Error?e.message:'Cannot read private payment queue')}finally{setBusy(false)}}
 useEffect(()=>{void load()},[])
 const choose=(order:Order)=>{setSelected(order);setBankRef('');setBankAmount('');setRecipient('');setNote('');setReceived(false);setPayer(false);setNotice('');setError('')}
 const review=async(action:'verify'|'reject')=>{
   if(!selected)return
   setBusy(true);setError('');setNotice('')
   try {
     const payload={note,bank_reference:bankRef.trim(),bank_amount_minor:Math.round(Number(bankAmount)*100),
       recipient,bank_confirmed:received,confirmed_payer:payer}
     const {error:problem}=await client.rpc('mela_billing_review_v1',{
       p_order_id:selected.id,p_action:action,p_data:payload
     })
     if(problem)throw problem
     setNotice(action==='verify'?'Verified payment and activated subscription. Referral reward remains pending review.':'Payment rejected; no subscription activated.')
     setSelected(null);await load()
   }catch(e){setError(e instanceof Error?e.message:'Payment review failed')}finally{setBusy(false)}
 }
 return <section className="panel">
   <div className="module-head"><div><h2>Pro/Premium verified payments</h2>
   <p>Manual incoming-transfer review only. User-submitted references are not proof of payment.
   Never verify without checking the real bank or Telebirr incoming record. No automated commission payouts.</p></div>
   <button className="refresh" disabled={busy} onClick={()=>void load()}><RefreshCw size={15}/>Refresh</button></div>
   {error&&<p className="error" role="alert"><AlertTriangle size={16}/>{error}</p>}
   {notice&&<p role="status">{notice}</p>}
   <div className="table-wrap"><table><thead><tr><th>Order</th><th>Account</th><th>Amount</th><th>Claimed ref</th><th>Status</th><th/></tr></thead><tbody>
   {orders.map(o=><tr key={o.id}><td>{o.plan_key==='pro_monthly'?'Pro':'Premium'}</td><td>{o.user_id}</td><td>{o.amount_minor/100} ETB</td><td>{o.claimed_reference||'—'}</td><td>{o.status}</td><td><button disabled={busy||o.status!=='pending_review'} onClick={()=>choose(o)}>Review</button></td></tr>)}
   {!orders.length&&<tr><td colSpan={6}>No subscription payments found.</td></tr>}
   </tbody></table></div>
   {selected&&<div className="detail-card"><h3>Independently verify incoming transfer</h3>
     <p>Expected: <strong>{selected.amount_minor/100} ETB</strong> · {selected.method_code} · recipient {selected.recipient}. Claimed reference: {selected.claimed_reference}</p>
     <p className="muted">Check the bank/Telebirr account yourself. Exact destination and amount are mandatory. Any duplicate reference is rejected across MELA payment pipelines.</p>
     <label>Actual incoming bank reference<input value={bankRef} maxLength={64} onChange={e=>setBankRef(e.target.value)}/></label>
     <label>Amount actually received (ETB)<input inputMode="decimal" value={bankAmount} onChange={e=>setBankAmount(e.target.value)} placeholder="e.g. 50"/></label>
     <label>Confirmed receiving account<input value={recipient} onChange={e=>setRecipient(e.target.value)} placeholder="Enter account verified at bank"/></label>
     <label>Evidence note / rejection reason<textarea minLength={20} maxLength={500} value={note} onChange={e=>setNote(e.target.value)} /></label>
     <label><input type="checkbox" checked={received} onChange={e=>setReceived(e.target.checked)}/> I independently checked the actual settled bank transaction.</label>
     <label><input type="checkbox" checked={payer} onChange={e=>setPayer(e.target.checked)}/> I independently verified it belongs to this MELA payment.</label>
     <div className="toolbar">
       <button className="refresh" disabled={busy} onClick={()=>setSelected(null)}>Close</button>
       <button className="danger-btn" disabled={busy||note.trim().length<20} onClick={()=>void review('reject')}>Reject</button>
       <button className="refresh" disabled={busy||!received||!payer||!bankRef||!bankAmount||recipient!==selected.recipient||note.trim().length<20}
         onClick={()=>void review('verify')}><ShieldCheck size={16}/>Confirm verified incoming payment</button>
     </div></div>}
 </section>
}
