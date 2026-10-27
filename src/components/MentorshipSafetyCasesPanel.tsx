import { useEffect, useRef, useState } from 'react'
import type { SupabaseClient } from '@supabase/supabase-js'

type MentorshipCase={
  id:string;reporter_id:string|null;target_type:string;target_id:string|null;
  reason:string;details:string|null;status:string;created_at:string;
  assigned_to:string|null;resolution_notes:string|null
}
export default function MentorshipSafetyCasesPanel({client}:{client:SupabaseClient}) {
  const [cases,setCases]=useState<MentorshipCase[]>([])
  const [selected,setSelected]=useState<MentorshipCase|null>(null)
  const [decision,setDecision]=useState<'reviewing'|'resolved'|'dismissed'>('reviewing')
  const [notes,setNotes]=useState('')
  const [history,setHistory]=useState<Array<{decision:string;notes:string;created_at:string}>|null>(null)
  const [historyLoading,setHistoryLoading]=useState(false)
  const [revision,setRevision]=useState(0)
  const [loading,setLoading]=useState(true)
  const [busy,setBusy]=useState(false)
  const [error,setError]=useState('')
  const [notice,setNotice]=useState('')
  const lock=useRef(false)
  const historyRequest=useRef(0)
  const [loadFailed,setLoadFailed]=useState(false)

  useEffect(()=>{
    let active=true;setLoading(true);setError('');setLoadFailed(false)
    historyRequest.current++;setHistoryLoading(false);setSelected(null);setHistory(null);setCases([])
    void Promise.resolve(client.from('reports')
      .select('id,reporter_id,target_type,target_id,reason,details,status,created_at,assigned_to,resolution_notes')
      .in('target_type',['mentor_profile','mentorship_request','mentorship_session'])
      .order('created_at',{ascending:false}).limit(100))
      .then(({data,error:fetchError})=>{
        if(fetchError)throw new Error(fetchError.message)
        if(active)setCases((data??[]) as MentorshipCase[])
      }).catch((cause)=>{
        if(active){setLoadFailed(true);setError(cause instanceof Error?cause.message:'Could not read authorized mentorship safety cases.')}
      }).finally(()=>{if(active)setLoading(false)})
    return()=>{active=false;historyRequest.current++}
  },[client,revision])

  const decide=async(event:React.FormEvent)=>{
    event.preventDefault()
    if(!selected||lock.current||selected.status==='resolved'||selected.status==='dismissed')return
    if((decision==='resolved'||decision==='dismissed')&&notes.trim().length<30){
      setError('A closure needs at least 30 characters explaining the investigation and decision.')
      return
    }
    lock.current=true;setBusy(true);setError('');setNotice('')
    try{
      const {data,error:reviewError}=await client.rpc('review_mentorship_concern',{
        p_case_id:selected.id,p_status:decision,p_resolution_notes:notes.trim(),
      })
      if(reviewError)throw new Error(reviewError.message)
      if(data!==true)throw new Error('The server did not confirm the case decision.')
      setNotice('Mentorship safety case updated and audit trail recorded. Any mentor suspension is a separate documented decision.')
      setSelected(null);setNotes('');setDecision('reviewing');setRevision(n=>n+1)
    }catch(cause){
      setError(cause instanceof Error?cause.message:'Could not review mentorship safety case.')
    }finally{lock.current=false;setBusy(false)}
  }

  const loadHistory=async()=>{
    if(!selected||historyLoading)return
    const request=++historyRequest.current
    setHistoryLoading(true);setError('');setHistory(null)
    try{
      const {data,error:rpcError}=await client.rpc('get_mentorship_case_review_history',{
        p_case_id:selected.id,
      })
      if(request!==historyRequest.current)return
      if(rpcError)throw new Error(rpcError.message)
      if(!Array.isArray(data))throw new Error('Confidential case history could not be verified.')
      setHistory(data.filter((v):v is {decision:string;notes:string;created_at:string}=>
        v!==null&&typeof v==='object'&&typeof v.decision==='string'
        &&typeof v.notes==='string'&&typeof v.created_at==='string'))
    }catch(cause){
      if(request===historyRequest.current)setError(cause instanceof Error?cause.message:'Could not load protected case history.')
    }finally{if(request===historyRequest.current)setHistoryLoading(false)}
  }

  const open=cases.filter(c=>c.status==='open'||c.status==='reviewing')
  return <section className="panel" aria-label="Mentorship safeguarding case review">
    <h2>Mentorship safeguarding cases</h2>
    <p>Private reports about verified mentors and participant requests/sessions. This queue is available only through an authorized administrator route; decisions additionally require MFA AAL2 at the database. Do not copy evidence or learner contact details outside approved case management.</p>
    <button type="button" disabled={busy||loading} onClick={()=>setRevision(n=>n+1)}>Refresh safety cases</button>
    {notice&&<p role="status">{notice}</p>}
    {error&&<p role="alert" className="error">{error}</p>}
    {loading?<p role="status">Loading authorized reports…</p>:loadFailed?null:
      <><p><strong>{open.length}</strong> open or under review (within the 100 most recent reports shown).</p>
        {cases.length===0?<p>No mentorship-specific safety cases have been submitted.</p>:
          <div className="table-wrap"><table>
            <thead><tr><th>Reason</th><th>Target</th><th>Status</th><th>Review</th></tr></thead>
            <tbody>{cases.map(report=><tr key={report.id}>
              <td><strong>{report.reason}</strong><small>Case {report.id.slice(0,8)} · {new Date(report.created_at).toLocaleDateString()}</small></td>
              <td>{report.target_type.replaceAll('_',' ')}</td>
              <td>{report.status}</td>
              <td><button type="button" disabled={busy} onClick={()=>{
                  historyRequest.current++;setHistoryLoading(false);setSelected(report);setDecision(report.status==='reviewing'?'resolved':'reviewing')
                  setNotes('');setError('');setHistory(null)
                }}>{['open','reviewing'].includes(report.status)?'Review case':'View closed case'}</button></td>
            </tr>)}</tbody>
          </table></div>}
      </>}
    {selected&&<form className="panel" onSubmit={decide}>
      <h3>Safeguarding review — {selected.reason}</h3>
      <p>Submitted account: {selected.reporter_id?.slice(0,8)||'Not provided'} · Target case: {selected.target_id?.slice(0,8)||'Not provided'}</p>
      <p style={{whiteSpace:'pre-wrap',overflowWrap:'anywhere'}}><strong>Reported concern:</strong> {selected.details||'No additional context'}</p>
      <button type="button" disabled={historyLoading} onClick={()=>void loadHistory()}>
        {historyLoading?'Loading confidential history…':'View confidential review history'}
      </button>
      {history&&<div aria-label="Confidential administrator review history">
        <h4>Restricted review history</h4>
        {history.length===0?<p>No internal decisions recorded yet.</p>:
          <ul>{history.map((entry,index)=><li key={entry.created_at+index}>
            <strong>{entry.decision}</strong> · {new Date(entry.created_at).toLocaleString()}
            <p style={{whiteSpace:'pre-wrap',overflowWrap:'anywhere'}}>{entry.notes}</p>
          </li>)}</ul>}
      </div>}
      {['open','reviewing'].includes(selected.status)&&<>
      <label>Decision
        <select disabled={busy} value={decision} onChange={event=>setDecision(event.target.value as typeof decision)}>
          {selected.status==='open'&&<option value="reviewing">Begin investigation</option>}
          <option value="resolved">Resolve after investigation</option>
          <option value="dismissed">Dismiss with documented reason</option>
        </select>
      </label>
      <label>Case review notes (minimum 30 characters to close)
        <textarea rows={5} maxLength={4000} disabled={busy} value={notes}
          onChange={event=>setNotes(event.target.value)}
          placeholder="Describe evidence examined and the safety action. Do not paste learner credentials or identity documents."/>
      </label>
      <button disabled={busy||((decision==='resolved'||decision==='dismissed')&&notes.trim().length<30)}>
        {busy?'Recording decision…':'Record reviewed decision'}
      </button>{' '}
      </>}
      <button type="button" disabled={busy} onClick={()=>{historyRequest.current++;setHistoryLoading(false);setSelected(null);setHistory(null)}}>Close case view</button>
      <p>For imminent safety risks, follow your organization's urgent safeguarding procedure. Closing a report does not automatically reactivate or suspend a mentor.</p>
    </form>}
  </section>
}
