import {useEffect,useRef,useState} from 'react'
import type {SupabaseClient} from '@supabase/supabase-js'

type GuardianRow = {
  id:string
  learner_id:string
  guardian_user_id:string|null
  relationship:string
  status:string
  requested_at:string
  notes:string|null
}
export default function GuardianConsentReviewPanel({client}:{client:SupabaseClient}) {
  const lock=useRef(false)
  const [rows,setRows]=useState<GuardianRow[]>([])
  const [chosen,setChosen]=useState<GuardianRow|null>(null)
  const [decision,setDecision]=useState<'verified'|'rejected'|''>('')
  const [evidence,setEvidence]=useState('')
  const [checked,setChecked]=useState(false)
  const [busy,setBusy]=useState(false)
  const [error,setError]=useState('')
  const [notice,setNotice]=useState('')
  const [revision,setRevision]=useState(0)
  useEffect(()=>{
    let active=true
    setBusy(true);setError('')
    void (async()=>{
      try{
        const {data,error:queryError}=await client.from('guardian_relationships')
          .select('id,learner_id,guardian_user_id,relationship,status,requested_at,notes')
          .eq('status','pending').order('requested_at',{ascending:true}).limit(100)
        if(queryError)throw queryError
        if(active)setRows((data??[]) as GuardianRow[])
      }catch(e){if(active)setError(e instanceof Error?e.message:'Guardian queue cannot be loaded. Check MFA and permissions.')}
      finally{if(active)setBusy(false)}
    })()
    return ()=>{active=false}
  },[client,revision])

  const submit=async(e:React.FormEvent)=>{
    e.preventDefault()
    if(lock.current||!chosen||!decision||!checked||evidence.trim().length<12)return
    if(decision==='verified'&&!chosen.guardian_user_id){
      setError('A linked, authenticated parent account is required before guardian verification.');return
    }
    lock.current=true;setBusy(true);setError('');setNotice('')
    try{
      const {error:reviewError}=await client.rpc('review_guardian_consent',{
        p_relationship_id:chosen.id,p_decision:decision,p_notes:evidence.trim(),
      })
      if(reviewError)throw reviewError
      setNotice('Guardian decision saved by MFA-authorized reviewer. Student access remains subject to server-side safeguards.')
      setChosen(null);setDecision('');setEvidence('');setChecked(false);setRevision(v=>v+1)
    }catch(err){setError(err instanceof Error?err.message:'Guardian review could not be saved.')}
    finally{lock.current=false;setBusy(false)}
  }
  return <section className="panel" aria-label="Guardian relationship review">
    <div className="module-head"><div><h2>Guardian relationship verification</h2><p>Review pending learner–guardian connections. An invitation code is not guardian identity verification. Decisions require MFA and an evidence note.</p></div><button onClick={()=>setRevision(v=>v+1)} disabled={busy}>Refresh</button></div>
    {error&&<div role="alert" className="error">{error}</div>}
    {notice&&<p role="status">{notice}</p>}
    {chosen&&<form className="detail-card" onSubmit={e=>void submit(e)}>
      <h3>Review guardian relationship</h3>
      <p>Learner record: {chosen.learner_id.slice(0,8)}… · Parent record: {chosen.guardian_user_id?.slice(0,8)??'Not linked'}…</p>
      <p>Independently verify parent identity, authority, learner relationship, and consent using your approved safeguarding procedure. Do not approve merely because a code was redeemed.</p>
      <label>Decision<select value={decision} onChange={e=>setDecision(e.target.value as 'verified'|'rejected'|'')} disabled={busy} required><option value="">Choose decision</option><option value="verified">Verified — evidence independently checked</option><option value="rejected">Reject</option></select></label>
      <label>Evidence and decision notes<textarea value={evidence} onChange={e=>setEvidence(e.target.value)} required minLength={12} maxLength={1000} disabled={busy} placeholder="Reference the verification evidence checked without copying sensitive documents."/></label>
      <label><input type="checkbox" checked={checked} onChange={e=>setChecked(e.target.checked)} disabled={busy}/> I performed an independent identity/relationship review and understand this decision grants child-data access.</label>
      <button disabled={busy||!checked||!decision||evidence.trim().length<12||(decision==='verified'&&!chosen.guardian_user_id)}>{busy?'Saving…':'Save reviewed decision'}</button>
      <button type="button" disabled={busy} onClick={()=>setChosen(null)}>Cancel</button>
    </form>}
    <div className="table-wrap"><table><thead><tr><th>Requested</th><th>Relationship</th><th>Linked parent</th><th>Action</th></tr></thead><tbody>
      {rows.map(row=><tr key={row.id}><td>{new Date(row.requested_at).toLocaleDateString()}</td><td>{row.relationship}</td><td>{row.guardian_user_id?'Linked — not yet verified':'No parent account linked'}</td><td><button disabled={busy} onClick={()=>{setChosen(row);setDecision('');setEvidence('');setChecked(false);setError('')}}>Review</button></td></tr>)}
      {!busy&&!rows.length&&<tr><td colSpan={4}>No pending guardian reviews.</td></tr>}
    </tbody></table></div>
  </section>
}
