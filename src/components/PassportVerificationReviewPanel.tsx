import { useEffect, useRef, useState } from 'react'
import type { SupabaseClient } from '@supabase/supabase-js'
type RequestRow = {
  id: string; record_kind: 'education' | 'experience'; record_id: string;
  user_id: string; record_name: string; record_details: string;
  applicant_note: string; requested_at: string
}
/** Direct calls are subject to server-side super-admin and AAL2 checks. */
export default function PassportVerificationReviewPanel({client}: {client: SupabaseClient}) {
  const [rows,setRows] = useState<RequestRow[]>([])
  const [selected,setSelected] = useState<RequestRow | null>(null)
  const [decision,setDecision] = useState<'approved'|'rejected'>('rejected')
  const [source,setSource] = useState('')
  const [feedback,setFeedback] = useState('')
  const [busy,setBusy] = useState(false)
  const [error,setError] = useState('')
  const [message,setMessage] = useState('')
  const lock=useRef(false)
  const refresh = async () => {
    setBusy(true);setError('')
    try {
      const {data,error} = await client.rpc('get_passport_verification_queue',{p_limit:50})
      if(error) throw error
      setRows(Array.isArray(data)?data:[])
    } catch(e) {
      setError(e instanceof Error?e.message:'Could not load verification requests.')
    } finally {setBusy(false)}
  }
  useEffect(()=>{void refresh()},[client])
  const submit = async () => {
    if(!selected || lock.current)return
    lock.current=true;setBusy(true);setError('');setMessage('')
    try{
      const {data,error}=await client.rpc('review_passport_verification_request',{
        p_request_id:selected.id, p_decision:decision, p_source:source.trim(),
        p_feedback:feedback.trim(),
      })
      if(error) throw error
      if(data!==decision) throw new Error('The decision could not be confirmed.')
      setMessage('Verification decision saved with an audit log and learner notification.')
      setSelected(null);setSource('');setFeedback('');await refresh()
    } catch(e) {setError(e instanceof Error?e.message:'Verification decision failed.')}
    finally {lock.current=false;setBusy(false)}
  }
  return <section className="panel" aria-label="Career Passport verification review">
    <h2>Career Passport verification</h2>
    <p>Only an MFA-authorized administrator may approve a claim. The learner's record is self-reported: verify the institution, role, dates and evidence independently before approving. No automatic verification is performed.</p>
    <button type="button" disabled={busy} onClick={()=>void refresh()}>Refresh passport requests</button>
    {busy && <p role="status">Loading or saving verification records…</p>}
    {error && <div className="error" role="alert">{error}</div>}
    {message && <p role="status">{message}</p>}
    {selected && <form className="panel" aria-label="Passport verification decision" onSubmit={e=>{e.preventDefault();void submit()}}>
      <h3>{selected.record_kind} — {selected.record_name}</h3>
      <p>{selected.record_details}</p>
      <p>Student statement: {selected.applicant_note||'None provided'}</p>
      <label>Review decision<select value={decision} disabled={busy} onChange={e=>setDecision(e.target.value as 'approved'|'rejected')}>
        <option value="rejected">Decline verification</option><option value="approved">Approve verified claim</option>
      </select></label>
      {decision==='approved'&&<label>Independent verification source
        <input required minLength={5} maxLength={300} disabled={busy} value={source} onChange={e=>setSource(e.target.value)} placeholder="How you confirmed this independently"/>
      </label>}
      <label>Review feedback (10–1500 characters)
        <textarea required minLength={10} maxLength={1500} disabled={busy} value={feedback} onChange={e=>setFeedback(e.target.value)}/>
      </label>
      <p>This approval is not a platform-access decision. It changes only this specific Career Passport record and creates an audit entry.</p>
      <button type="submit" disabled={busy||feedback.trim().length<10||(decision==='approved'&&source.trim().length<5)}>
        {busy?'Saving…':'Confirm passport decision'}
      </button>
      <button type="button" disabled={busy} onClick={()=>{setSelected(null);setError('')}}>Cancel</button>
    </form>}
    <div className="table-wrap"><table><thead><tr><th>Kind</th><th>Record</th><th>Applicant context</th><th>Requested</th><th>Action</th></tr></thead>
      <tbody>{rows.map(row=><tr key={row.id}>
        <td>{row.record_kind}</td><td>{row.record_name}<small>{row.record_details}</small></td>
        <td>{row.applicant_note||'No note'}</td>
        <td>{new Date(row.requested_at).toLocaleDateString()}</td>
        <td><button disabled={busy} onClick={()=>{setSelected(row);setDecision('rejected');setSource('');setFeedback('');setError('');setMessage('')}}>Review claim</button></td>
      </tr>)}</tbody>
    </table></div>
    {!busy && !error && rows.length===0 && <p>No pending Career Passport verification requests.</p>}
  </section>
}
