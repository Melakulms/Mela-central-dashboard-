import {useEffect,useRef,useState} from 'react'
import type {SupabaseClient} from '@supabase/supabase-js'

type CredentialDocument={
 id:string;teacher_id:string;document_kind:string;original_name:string;
 storage_path:string;review_status:'pending'|'approved'|'rejected';
 review_note:string|null;uploaded_at:string;reviewed_at:string|null
}

const LABELS:Record<string,string>={
 degree:'University degree',diploma:'Diploma',teaching_license:'Teaching license',
 professional_certificate:'Professional certificate',other:'Other supporting qualification',
}

/** Only a current MFA-authorized admin can fetch the documents and issue
 * short-lived private download links. Never put the service role in the browser.
 */
export default function TeacherDocumentReview({client,teacherId}:{client:SupabaseClient;teacherId:string}){
 const [documents,setDocuments]=useState<CredentialDocument[]>([])
 const [loading,setLoading]=useState(true)
 const [busy,setBusy]=useState(false)
 const [error,setError]=useState('')
 const [message,setMessage]=useState('')
 const [selected,setSelected]=useState<string|null>(null)
 const [decision,setDecision]=useState<'approved'|'rejected'>('approved')
 const [note,setNote]=useState('')
 const [revision,setRevision]=useState(0)
 const guard=useRef(false)
 useEffect(()=>{
  let active=true
  setLoading(true);setError('');setSelected(null)
  void client.from('teacher_credential_documents')
    .select('id,teacher_id,document_kind,original_name,storage_path,review_status,review_note,uploaded_at,reviewed_at')
    .eq('teacher_id',teacherId).order('uploaded_at',{ascending:false})
    .then(({data,error})=>{
      if(!active)return
      if(error)throw error
      setDocuments((data??[]) as CredentialDocument[])
    }).catch((cause:unknown)=>{
      if(active)setError(cause instanceof Error?cause.message:'Could not load the teacher documents.')
    }).finally(()=>{if(active)setLoading(false)})
  return()=>{active=false}
 },[client,teacherId,revision])

 async function openPrivateDocument(doc:CredentialDocument){
  if(busy)return
  // Reserve the new window synchronously (Android browsers block async popups).
  const win=window.open('about:blank','_blank')
  try{
   if(win)win.opener=null
   setError('')
   const {data,error}=await client.storage.from('teacher-credentials').createSignedUrl(doc.storage_path,60)
   if(error||!data?.signedUrl)throw error??new Error('Unable to open the private document.')
   // This URL expires in 60 seconds; no permanent or public link is published.
   if(win)win.location.replace(data.signedUrl)
   else setError('Allow pop-ups in your browser to open this private document.')
  }catch(cause){
   if(win)win.close()
   setError(cause instanceof Error?cause.message:'Could not open the private document.')
  }
 }

 async function record(event:React.MouseEvent<HTMLButtonElement>){
  event.preventDefault()
  if(guard.current||!selected||note.trim().length<8)return
  guard.current=true;setBusy(true);setError('');setMessage('')
  try{
   const {error}=await client.rpc('review_teacher_credential_document',{
    p_document_id:selected,p_decision:decision,p_note:note.trim(),
   })
   if(error)throw error
   setMessage(decision==='approved'?'Credential evidence approved and audited. You may now decide whether to approve the teacher.':'Credential rejected and audited. Ask the teacher for corrected evidence.')
   setSelected(null);setNote('');setRevision(value=>value+1)
  }catch(cause){setError(cause instanceof Error?cause.message:'Document review could not be saved.')}
  finally{guard.current=false;setBusy(false)}
 }

 const approved=documents.filter(doc=>doc.review_status==='approved').length
 return <section aria-label="Teacher qualification documents" className="panel">
  <h4>Qualification documents · secure review</h4>
  <p>View each certificate in a short-lived private window. Compare the name, issuing institution, course, dates and subjects against the teacher profile. Verify independently before approval. Email confirmation alone is not evidence.</p>
  <p role="status">{loading?'Loading private evidence…':`${documents.length} uploaded · ${approved} approved`}</p>
  {error&&<div role="alert" className="error">{error}</div>}
  {message&&<p role="status">{message}</p>}
  {!loading&&documents.length===0&&<p>No documents submitted yet. Ask this teacher to sign in to MELA Users → Teacher Dashboard → Qualifications &amp; documents, upload a teaching credential, then return here.</p>}
  {documents.map(doc=><div key={doc.id} className="detail-card">
   <strong>{LABELS[doc.document_kind]??'Teaching credential'} · {doc.original_name}</strong>
   <p>Review status: <strong>{doc.review_status}</strong> · Submitted {new Date(doc.uploaded_at).toLocaleDateString()}</p>
   {doc.review_note&&<p>Prior review note: {doc.review_note}</p>}
   <div className="toolbar">
    <button type="button" disabled={busy} onClick={()=>void openPrivateDocument(doc)}>View private document (60-second link)</button>
    <button type="button" disabled={busy} onClick={()=>{setSelected(doc.id);setDecision('approved');setNote('');setError('');setMessage('')}}>Review evidence</button>
   </div>
   {selected===doc.id&&<div className="detail-card">
    <label>Document decision<select value={decision} disabled={busy}
      onChange={event=>setDecision(event.target.value as 'approved'|'rejected')}>
      <option value="approved">Approve independently checked document</option>
      <option value="rejected">Reject / request replacement</option>
    </select></label>
    <label>Verification evidence and reason<textarea required value={note} disabled={busy}
      minLength={8} maxLength={2000} placeholder="Example: Verified certificate serial number with the issuing institution on [date]."
      onChange={event=>setNote(event.target.value)}/></label>
    <button type="button" disabled={busy||note.trim().length<8} onClick={event=>void record(event)}>
      {busy?'Saving…':'Save audited document decision'}</button>
    <button type="button" disabled={busy} onClick={()=>setSelected(null)}>Cancel</button>
   </div>}
  </div>)}
 </section>
}
