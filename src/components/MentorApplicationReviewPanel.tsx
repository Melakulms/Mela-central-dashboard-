import {useEffect,useRef,useState} from 'react'
import type {SupabaseClient} from '@supabase/supabase-js'

type Application = {
  applicant_id:string
  headline:string
  expertise:string[]
  languages:string[]
  background:string
  status:string
  review_notes:string|null
  submitted_at:string
}
export default function MentorApplicationReviewPanel({client}:{client:SupabaseClient}) {
  const saving=useRef(false)
  const [rows,setRows]=useState<Application[]>([])
  const [chosen,setChosen]=useState<Application|null>(null)
  const [decision,setDecision]=useState<'reviewed_eligible'|'rejected'|''>('')
  const [notes,setNotes]=useState('')
  const [checked,setChecked]=useState(false)
  const [busy,setBusy]=useState(false)
  const [error,setError]=useState('')
  const [success,setSuccess]=useState('')
  const [revision,setRevision]=useState(0)

  useEffect(()=>{
    let active=true;setBusy(true);setError('')
    void (async()=>{
      try{
        const {data,error}=await client.from('mentorship_applications')
          .select('applicant_id,headline,expertise,languages,background,status,review_notes,submitted_at')
          .eq('status','pending_review').order('submitted_at',{ascending:true}).limit(100)
        if(error)throw error
        if(active)setRows((data??[]) as Application[])
      }catch(e){if(active)setError(e instanceof Error?e.message:'Mentor application review queue unavailable.')}
      finally{if(active)setBusy(false)}
    })()
    return ()=>{active=false}
  },[client,revision])

  const submit=async(e:React.FormEvent)=>{
    e.preventDefault()
    if(saving.current||!chosen||!checked||!decision||notes.trim().length<12)return
    saving.current=true;setBusy(true);setError('');setSuccess('')
    try{
      // Column-limited grant + admin MFA RLS allow only review fields to change.
      // This does NOT set mentor_profiles.verified or promote the applicant role.
      const {data,error}=await client.from('mentorship_applications')
        .update({status:decision,review_notes:notes.trim()})
        .eq('applicant_id',chosen.applicant_id).eq('status','pending_review')
        .select('applicant_id').maybeSingle()
      if(error)throw error
      if(!data)throw new Error('This application was already reviewed. Refresh the queue.')
      setSuccess(decision==='reviewed_eligible'
        ? 'Eligibility review recorded. Mentor account activation and safeguarding authorization remain separate.'
        : 'Application rejection recorded.')
      setChosen(null);setNotes('');setChecked(false);setDecision('');setRevision(v=>v+1)
    }catch(e){setError(e instanceof Error?e.message:'Could not save eligibility review.')}
    finally{saving.current=false;setBusy(false)}
  }
  return <section className="panel" aria-label="Mentor eligibility application review">
    <div className="module-head"><div><h2>Mentor eligibility review</h2><p>Review submitted expertise and background. A positive eligibility review is NOT mentor verification and must not create session-booking permissions.</p></div><button disabled={busy} onClick={()=>setRevision(v=>v+1)}>Refresh</button></div>
    {error&&<div className="error" role="alert">{error}</div>}
    {success&&<p role="status">{success}</p>}
    {chosen&&<form className="detail-card" onSubmit={e=>void submit(e)}>
      <h3>{chosen.headline}</h3>
      <p>Applicant record: {chosen.applicant_id.slice(0,8)}…</p>
      <dl><dt>Expertise</dt><dd>{chosen.expertise.join(', ')}</dd><dt>Languages</dt><dd>{chosen.languages.join(', ')}</dd><dt>Background</dt><dd style={{whiteSpace:'pre-wrap'}}>{chosen.background}</dd></dl>
      <label>Decision<select value={decision} onChange={e=>setDecision(e.target.value as 'reviewed_eligible'|'rejected'|'')} required disabled={busy}><option value="">Choose review decision</option><option value="reviewed_eligible">Eligible for separate mentor verification</option><option value="rejected">Reject application</option></select></label>
      <label>Evidence note<textarea required minLength={12} maxLength={1000} value={notes} onChange={e=>setNotes(e.target.value)} disabled={busy}/></label>
      <label><input type="checkbox" checked={checked} onChange={e=>setChecked(e.target.checked)} disabled={busy}/> I independently checked eligibility evidence; I understand this does not activate a mentor.</label>
      <button disabled={busy||!checked||!decision||notes.trim().length<12}>{busy?'Saving…':'Save eligibility decision'}</button>
      <button type="button" disabled={busy} onClick={()=>setChosen(null)}>Cancel</button>
    </form>}
    <div className="table-wrap"><table><thead><tr><th>Submitted</th><th>Professional title</th><th>Expertise</th><th>Action</th></tr></thead><tbody>
      {rows.map(row=><tr key={row.applicant_id}><td>{new Date(row.submitted_at).toLocaleDateString()}</td><td>{row.headline}</td><td>{row.expertise.join(', ')}</td><td><button disabled={busy} onClick={()=>{setChosen(row);setDecision('');setNotes('');setChecked(false);setError('')}}>Review evidence</button></td></tr>)}
      {!busy&&!rows.length&&<tr><td colSpan={4}>No new mentor eligibility applications.</td></tr>}
    </tbody></table></div>
  </section>
}
