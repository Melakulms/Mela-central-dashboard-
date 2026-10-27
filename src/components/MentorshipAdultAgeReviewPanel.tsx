import { useEffect, useRef, useState } from 'react'
import type { SupabaseClient } from '@supabase/supabase-js'

type PendingAgeReview={
 id:string;learner_id:string;claimed_date_of_birth:string;
 status:string;created_at:string;
}
export default function MentorshipAdultAgeReviewPanel({client}:{client:SupabaseClient}){
 const [rows,setRows]=useState<PendingAgeReview[]>([])
 const [selected,setSelected]=useState<PendingAgeReview|null>(null)
 const [verifiedEvidence,setVerifiedEvidence]=useState(false)
 const [notes,setNotes]=useState('')
 const [error,setError]=useState('')
 const [notice,setNotice]=useState('')
 const [loading,setLoading]=useState(true)
 const [busy,setBusy]=useState(false)
 const [revision,setRevision]=useState(0)
 const lock=useRef(false)

 useEffect(()=>{
  let active=true
  setLoading(true);setError('')
    setRows([]);setSelected(null);setNotes('');setVerifiedEvidence(false)
  void (async()=>{
    try{
      const {data,error:readError}=await client.from('mentorship_adult_age_reviews')
        .select('id,learner_id,claimed_date_of_birth,status,created_at')
        .eq('status','pending').order('created_at',{ascending:true}).limit(100)
      if(readError)throw new Error(readError.message)
      if(active)setRows((data??[]) as PendingAgeReview[])
    }catch(cause){
      if(active)setError(cause instanceof Error?cause.message:'Age review queue unavailable.')
    }finally{if(active)setLoading(false)}
  })()
  return()=>{active=false}
 },[client,revision])

 const review=async(event:React.FormEvent,decision:'approved'|'declined')=>{
  event.preventDefault()
  if(!selected||lock.current||notes.trim().length<30 || (decision==='approved'&&!verifiedEvidence))return
  lock.current=true;setBusy(true);setNotice('');setError('')
  try{
    const {data:auth,error:authError}=await client.auth.getUser()
    if(authError)throw authError
    if(!auth.user)throw new Error('MFA administrator sign-in required')
    const {data,error:reviewError}=await client.from('mentorship_adult_age_reviews')
      .update({
        status:decision,reviewer_id:auth.user.id,
        reviewed_at:new Date().toISOString(),reviewer_notes:notes.trim(),
      }).eq('id',selected.id).eq('status','pending').select('id')
    if(reviewError)throw new Error(reviewError.message)
    if(!data?.length)throw new Error('Review was already decided or MFA administrator access was denied.')
    setNotice(decision==='approved'
      ?'Adult mentorship eligibility recorded after review. The server updated the protected birth date and audit log.'
      :'Application declined and review recorded.')
    setSelected(null);setNotes('');setVerifiedEvidence(false);setRevision(n=>n+1)
  }catch(cause){
    setError(cause instanceof Error?cause.message:'Could not save adult review.')
  }finally{setBusy(false);lock.current=false}
 }

 return <section className="panel" aria-label="MELA mentorship adult age verification">
  <h2>Private adult age review queue</h2>
  <p>University and TVET applicants submit a claimed birth date and safeguarding acknowledgement. Before approving, an MFA-verified administrator must independently check identity and age against a trusted record. Do not approve based on the learner's declaration alone.</p>
  <button type="button" disabled={loading||busy} onClick={()=>setRevision(n=>n+1)}>Refresh age reviews</button>
  {error&&<p role="alert" className="error">{error}</p>}
  {notice&&<p role="status">{notice}</p>}
  {loading?<p role="status">Loading private age reviews…</p>:
    rows.length===0?<p>No pending adult eligibility reviews.</p>:
    <div className="table-wrap"><table>
      <thead><tr><th>Review</th><th>Claimed date of birth</th><th>Submitted</th><th>Decision</th></tr></thead>
      <tbody>{rows.map(row=><tr key={row.id}>
        <td>{row.id.slice(0,8)}</td>
        <td>{row.claimed_date_of_birth}</td>
        <td>{new Date(row.created_at).toLocaleDateString()}</td>
        <td><button type="button" disabled={busy} onClick={()=>{
          setSelected(row);setVerifiedEvidence(false);setNotes('');setError('')
        }}>Review privately</button></td>
      </tr>)}</tbody>
    </table></div>}
  {selected&&<div className="panel" aria-label="Private adult mentorship review form">
    <h3>Review adult eligibility</h3>
    <p>Submitted birth date: <strong>{selected.claimed_date_of_birth}</strong>. This is sensitive information; don't include it or identity document numbers in review notes.</p>
    <label><input type="checkbox" disabled={busy} checked={verifiedEvidence}
      onChange={e=>setVerifiedEvidence(e.target.checked)}/>
      I independently checked the learner's age using approved identity evidence and confirmed they are an adult.</label>
    <label>Evidence source, verification method and justification
      <textarea required rows={4} minLength={30} maxLength={2000}
        disabled={busy} value={notes} onChange={e=>setNotes(e.target.value)}/>
    </label>
    <button type="button" disabled={busy||!verifiedEvidence||notes.trim().length<30}
      onClick={event=>void review(event,'approved')}>Approve verified adult</button>{' '}
    <button type="button" disabled={busy||notes.trim().length<30}
      onClick={event=>void review(event,'declined')}>Decline request</button>{' '}
    <button type="button" disabled={busy} onClick={()=>setSelected(null)}>Cancel</button>
    <p className="muted">Only a verified administrator can change protected student birth dates. Decisions are audited; this form does not enable mentoring to unverified mentors or children.</p>
  </div>}
 </section>
}
