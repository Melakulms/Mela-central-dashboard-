import { useEffect,useRef,useState } from 'react'
import type { SupabaseClient } from '@supabase/supabase-js'

type Claim={id:string;learner_id:string;mentor_id:string;category:string;outcome_text:string;review_notes:string|null;status:string;created_at:string}
type Review={claim_id:string;decision:string;reviewed_at:string}
type Decision='evidence_supported'|'evidence_rejected'

export default function MentorshipIndependentOutcomePanel({client}:{client:SupabaseClient}){
 const [claims,setClaims]=useState<Claim[]>([])
 const [reviews,setReviews]=useState<Review[]>([])
 const [selected,setSelected]=useState<string|null>(null)
 const [decision,setDecision]=useState<Decision>('evidence_supported')
 const [reason,setReason]=useState('')
 const [confirmed,setConfirmed]=useState(false)
 const [revision,setRevision]=useState(0)
 const [loading,setLoading]=useState(true)
 const [busy,setBusy]=useState(false)
 const [error,setError]=useState('')
 const [notice,setNotice]=useState('')
 const lock=useRef(false)

 useEffect(()=>{
  let active=true
  setLoading(true);setClaims([]);setReviews([]);setSelected(null);setReason('');setConfirmed(false);setError('')
  void(async()=>{
   try{
    const [c,r]=await Promise.all([
      client.from('mentorship_outcome_claims')
        .select('id,learner_id,mentor_id,category,outcome_text,review_notes,status,created_at')
        .eq('status','mentor_supported').order('created_at',{ascending:false}).limit(100),
      client.from('mentorship_outcome_verifications')
        .select('claim_id,decision,reviewed_at').order('reviewed_at',{ascending:false}).limit(100),
    ])
    if(c.error)throw c.error
    if(r.error)throw r.error
    if(active){setClaims((c.data??[]) as Claim[]);setReviews((r.data??[]) as Review[])}
   }catch(cause){if(active)setError(cause instanceof Error?cause.message:'Independent evidence review could not load.')}
   finally{if(active)setLoading(false)}
  })()
  return()=>{active=false}
 },[client,revision])

 const reviewed=new Set(reviews.map(r=>r.claim_id))
 const pending=claims.filter(c=>!reviewed.has(c.id))
 const save=async()=>{
  if(lock.current||!selected||!confirmed||reason.trim().length<50||reason.trim().length>1000)return
  if(!pending.some(c=>c.id===selected)){setError('This claim is no longer in the pending review queue.');return}
  lock.current=true;setBusy(true);setError('');setNotice('')
  try{
   const {data:auth,error:authError}=await client.auth.getUser()
   if(authError)throw authError
   if(!auth.user)throw new Error('MFA reviewer sign-in is required.')
   const claim=pending.find(c=>c.id===selected)
   if(auth.user.id===claim?.learner_id||auth.user.id===claim?.mentor_id){
    throw new Error('Reviewer must be independent of the learner and mentor.')
   }
   const {data,error:writeError}=await client.from('mentorship_outcome_verifications')
     .insert({claim_id:selected,decision,public_reason:reason.trim(),reviewed_by:auth.user.id})
     .select('claim_id')
   if(writeError)throw new Error(writeError.message)
   if(!data?.length)throw new Error('No independent review was recorded; check permission and claim status.')
   setNotice('Independent evidence decision recorded and audited. No certificate or Career Passport award was issued.')
   setRevision(n=>n+1)
  }catch(cause){setError(cause instanceof Error?cause.message:'Could not save independent outcome review.')}
  finally{lock.current=false;setBusy(false)}
 }
 return <section className="panel" aria-label="Independent mentorship outcome review">
  <h2>Independent mentorship outcome evidence</h2>
  <p>Review only actual mentor-supported outcomes from completed sessions. A second, independent MFA administrator must inspect genuine evidence and record a reason. This is a narrative evidence decision, not a diploma, certificate, payment or Career Passport award. Do not include private identity documents or confidential case notes in the participant-visible explanation.</p>
  {error&&<div role="alert" className="error">{error}</div>}
  {notice&&<p role="status">{notice}</p>}
  <button type="button" disabled={loading||busy} onClick={()=>setRevision(n=>n+1)}>Refresh independent reviews</button>
  {loading?<p role="status">Loading mentor-supported outcomes…</p>:<>
   {!pending.length?<p>No unreviewed mentor-supported outcomes available.</p>:<div className="table-wrap"><table>
    <thead><tr><th>Outcome</th><th>Mentor review</th><th>Action</th></tr></thead>
    <tbody>{pending.map(c=><tr key={c.id}>
      <td><b>{c.category}</b><small>{c.outcome_text}</small></td>
      <td>{c.review_notes||'No mentor notes'}</td>
      <td><button type="button" disabled={busy} onClick={()=>{
        setSelected(c.id);setReason('');setConfirmed(false);setDecision('evidence_supported');setError('');setNotice('')
      }}>Independently review</button></td>
    </tr>)}</tbody>
   </table></div>}
   {selected&&pending.some(c=>c.id===selected)&&<div>
     <h3>Decision for claim {selected.slice(0,8)}</h3>
     <label>Evidence decision<select disabled={busy} value={decision}
       onChange={e=>setDecision(e.target.value as Decision)}>
       <option value="evidence_supported">Independent evidence supported</option>
       <option value="evidence_rejected">Evidence rejected</option>
     </select></label>
     <label>Participant-visible independent evidence explanation
       <textarea disabled={busy} maxLength={1000} value={reason} onChange={e=>setReason(e.target.value)}
         placeholder="Summarize the independently checked evidence and limitations in 50–1000 characters."/>
     </label>
     <label><input type="checkbox" checked={confirmed} disabled={busy}
       onChange={e=>setConfirmed(e.target.checked)}/> I independently examined appropriate evidence, checked safeguarding, and understand no qualification is awarded.</label>
     <button type="button" disabled={busy||!confirmed||reason.trim().length<50||reason.trim().length>1000}
       onClick={()=>void save()}>Record independent decision</button>
     <button type="button" disabled={busy} onClick={()=>setSelected(null)}>Cancel</button>
   </div>}
   <p className="muted">First 100 supported claims and 100 decisions are shown; older results need a separate audit review. No synthetic learner or session data is created.</p>
  </>}
 </section>
}
