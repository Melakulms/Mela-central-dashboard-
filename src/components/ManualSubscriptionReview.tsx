import {useEffect,useState} from 'react'
import type {SupabaseClient} from '@supabase/supabase-js'

type Pending = {id:string;user_id:string;amount_minor:number;currency:string;provider:string;recipient:string;reference:string|null;status:string;created_at:string;expires_at:string;reason:string|null}
type ReviewResult = {status:string;reason?:string;order_id?:string}

export default function ManualSubscriptionReview({client}:{client:SupabaseClient}){
 const [orders,setOrders]=useState<Pending[]>([])
 const [selected,setSelected]=useState<Pending|null>(null)
 const [reference,setReference]=useState('')
 const [paidAt,setPaidAt]=useState('')
 const [evidence,setEvidence]=useState('')
 const [received,setReceived]=useState(false)
 const [payerConfirmed,setPayerConfirmed]=useState(false)
 const [busy,setBusy]=useState(false)
 const [error,setError]=useState('')
 const [notice,setNotice]=useState('')
 const [loaded,setLoaded]=useState(false)
 const refresh=async()=>{
  setBusy(true);setError('')
  try{
   const {data,error}=await client.rpc('payment_command_v1',{p_action:'admin_queue',p_data:{}})
   if(error)throw error
   if(!Array.isArray(data))throw new Error('The payment reviewer queue returned an invalid response.')
   setOrders(data as Pending[])
  }catch(e){setOrders([]);setError(e instanceof Error?e.message:'The MFA payment reviewer is not configured.')}
  finally{setBusy(false);setLoaded(true)}
 }
 useEffect(()=>{void refresh()},[client])
 const verify=async()=>{
  if(!selected || busy)return
  if(!received || !payerConfirmed){setError('Bank receipt and payer/order owner confirmation are both required.');return}
  if(!reference || reference.trim().toUpperCase()!==selected.reference){setError('The actual bank reference must match the customer reference exactly.');return}
  if(evidence.trim().length<20 || !paidAt){setError('At least 20 characters of independent bank evidence and payment date are required.');return}
  setBusy(true);setError('');setNotice('')
  try{
   const payload={
    order_id:selected.id,
    confirmed_received:true,
    confirmed_order_owner:true,
    reference:reference.trim().toUpperCase(),
    recipient:selected.recipient,
    currency:selected.currency,
    amount_minor:selected.amount_minor,
    paid_at:new Date(paidAt).toISOString(),
    evidence_note:evidence.trim()
   }
   const {data,error}=await client.rpc('payment_command_v1',{p_action:'admin_record',p_data:payload})
   if(error)throw error
   const result=data as ReviewResult|null
   if(result?.status!=='approved')throw new Error(result?.reason??'The payment remains pending; do not tell the user they are subscribed.')
   setNotice('Verified bank record matched, the order was approved, and its receipt-linked membership was recorded.')
   setSelected(null);setReference('');setPaidAt('');setEvidence('');setReceived(false);setPayerConfirmed(false)
   await refresh()
  }catch(e){setError(e instanceof Error?e.message:'Verification failed. The order has not been marked approved.')}
  finally{setBusy(false)}
 }
 return <section className="panel" aria-label="Manual MELA subscription bank payment review">
  <div className="module-head"><div><h2>Verified subscription orders</h2><p>Only an MFA-authorized reviewer can confirm a real incoming bank or Telebirr record. A customer's transaction reference alone never approves a subscription.</p></div>
   <button type="button" onClick={()=>void refresh()} disabled={busy}>Refresh</button></div>
  {error&&<p className="error" role="alert">{error}</p>}
  {notice&&<p role="status">{notice}</p>}
  {!loaded&&<p role="status">Loading MFA-protected payment queue…</p>}
  {!orders.length&&loaded&&<p>No reviewable subscription orders. Do not ask customers to send transfers until checkout is enabled and reviewed.</p>}
  <div className="table-wrap"><table><thead><tr><th>Order</th><th>Amount</th><th>Receiving account</th><th>Claimed reference</th><th>Action</th></tr></thead>
   <tbody>{orders.map(order=><tr key={order.id}>
     <td>{order.id.slice(0,8)}…</td><td>{(order.amount_minor/100).toFixed(0)} {order.currency}</td>
     <td>{order.provider} — {order.recipient}</td><td>{order.reference??'Not submitted'}</td>
     <td><button type="button" disabled={!order.reference||busy} onClick={()=>{
        setSelected(order);setReference(order.reference??'');setEvidence('');setPaidAt('');
        setReceived(false);setPayerConfirmed(false);setNotice('');setError('')
       }}>Review incoming transfer</button></td>
    </tr>)}</tbody></table></div>
  {selected&&<div className="detail-card">
   <h3>Independently verify transaction</h3>
   <p>Check the actual bank or Telebirr receiving account and payer against order {selected.id}. Do not rely on screenshots, forwarded chats, or a reference alone.</p>
   <p>Expected: {(selected.amount_minor/100).toFixed(0)} {selected.currency} to {selected.recipient}</p>
   <label>Incoming bank reference<input value={reference} maxLength={64} onChange={e=>setReference(e.target.value.toUpperCase())} /></label>
   <label>Payment date and time<input type="datetime-local" value={paidAt} onChange={e=>setPaidAt(e.target.value)} /></label>
   <label>Private evidence note (min 20 characters)<textarea value={evidence} onChange={e=>setEvidence(e.target.value)} maxLength={500}/></label>
   <label><input type="checkbox" checked={received} onChange={e=>setReceived(e.target.checked)} /> I personally checked the settled incoming money in the receiving account.</label>
   <label><input type="checkbox" checked={payerConfirmed} onChange={e=>setPayerConfirmed(e.target.checked)} /> I independently checked that the payment belongs to this MELA user and order.</label>
   <div className="toolbar"><button type="button" disabled={busy} onClick={()=>setSelected(null)}>Cancel review</button><button type="button" disabled={busy||!received||!payerConfirmed||evidence.trim().length<20||!paidAt} onClick={()=>void verify()}>Record independently verified incoming transfer</button></div>
  </div>}
 </section>
}
