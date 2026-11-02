import { useEffect, useRef, useState } from 'react'
import { createAdminClient } from '../lib/admin-api'

// No identity documents are downloaded or uploaded through this panel.
// Staff must independently confirm adulthood using an authorized private process.
type Client = ReturnType<typeof createAdminClient>
type Review = {user_id:string;status:string;requested_at:string}

export default function WorkEligibilityReviewPanel({client}:{client:Client}) {
  const [rows,setRows] = useState<Review[]>([])
  const [selected,setSelected] = useState<Review|null>(null)
  const [note,setNote] = useState('')
  const [evidenceConfirmed,setEvidenceConfirmed] = useState(false)
  const [busy,setBusy] = useState(false)
  const [loading,setLoading] = useState(true)
  const [error,setError] = useState('')
  const [notice,setNotice] = useState('')
  const lock=useRef(false)

  const load=async()=>{
    setLoading(true);setError('')
    try {
      const {data,error:loadError}=await client.from('earn_work_eligibility_reviews')
        .select('user_id,status,requested_at')
        .eq('status','pending').order('requested_at',{ascending:true}).limit(100)
      if(loadError)throw loadError
      setRows((data??[]) as Review[])
    }catch(e){setError(e instanceof Error?e.message:'Could not load adult work reviews.')}
    finally{setLoading(false)}
  }
  useEffect(()=>{void load()},[])
  const decide=async(approved:boolean)=>{
    if(!selected||lock.current||note.trim().length<20||note.trim().length>500||!evidenceConfirmed)return
    if(approved&&!window.confirm('Confirm you independently verified this person is 18 or older using an authorized private process? No payout is activated.'))return
    lock.current=true;setBusy(true);setError('');setNotice('')
    try {
      const {data,error:reviewError}=await client.rpc('mela_review_work_eligibility_v1',{
        p_user_id:selected.user_id,p_approve:approved,p_note:note.trim(),
      })
      if(reviewError)throw reviewError
      if(data?.status!==(approved?'approved':'rejected'))throw new Error('Server did not confirm the review.')
      setNotice(approved?'Adult eligibility approved. Paid jobs and payouts remain separately gated.':'Request rejected and audit record saved.')
      setSelected(null);setNote('');setEvidenceConfirmed(false)
      await load()
    }catch(e){setError(e instanceof Error?e.message:'Unable to verify the review.')}
    finally{lock.current=false;setBusy(false)}
  }

  return <section className="panel" aria-label="Earn & Work adult verification review">
    <div className="module-head"><div><h2>Earn & Work — Adult identity reviews</h2>
      <p>Review requests from adult learners. Approval requires independent identity evidence, a current policy acknowledgement, an authorized MFA session and a server audit record.</p>
    </div><button className="refresh" type="button" disabled={busy||loading} onClick={()=>void load()}>Refresh</button></div>
    <p className="muted">Never request passports or ID numbers in public MELA messages. Do not approve based solely on a checkbox, profile education stage, Telegram username or transfer reference.</p>
    {loading&&<p role="status">Loading pending reviews…</p>}
    {error&&<div className="error" role="alert">{error}</div>}
    {notice&&<p role="status">{notice}</p>}
    {!loading&&!rows.length&&<p>No pending adult work verification requests.</p>}
    {!loading&&<div className="table-wrap"><table><thead><tr><th>Applicant account</th><th>Requested</th><th>Status</th><th>Review</th></tr></thead>
      <tbody>{rows.map(r=><tr key={r.user_id}><td>{r.user_id}</td>
        <td>{new Date(r.requested_at).toLocaleDateString()}</td><td>{r.status}</td>
        <td><button type="button" className="refresh" onClick={()=>{setSelected(r);setNote('');setEvidenceConfirmed(false);setError('')}}>Open review</button></td>
      </tr>)}</tbody></table></div>}
    {selected&&<div className="detail-card" aria-label="Selected adult work review">
      <h3>Independent verification decision</h3><p>Applicant account: {selected.user_id}</p>
      <p>Confirm identity and age through MELA's authorized private verification process before approval. Enter a non-sensitive audit note describing the verification channel and outcome, without document numbers or images.</p>
      <label htmlFor="adult-work-review-note">Verification note (20–500 characters)</label>
      <textarea id="adult-work-review-note" value={note} maxLength={500} onChange={e=>setNote(e.target.value)} disabled={busy}/>
      <label><input type="checkbox" checked={evidenceConfirmed} onChange={e=>setEvidenceConfirmed(e.target.checked)} disabled={busy}/>
        I independently checked the applicant's age/identity through an authorized process and did not rely on a self-declaration alone.</label>
      <div className="toolbar">
        <button type="button" className="refresh" disabled={busy||note.trim().length<20||!evidenceConfirmed} onClick={()=>void decide(false)}>Reject eligibility</button>
        <button type="button" disabled={busy||note.trim().length<20||!evidenceConfirmed} onClick={()=>void decide(true)}>Approve verified adult</button>
        <button type="button" className="refresh" disabled={busy} onClick={()=>{setSelected(null);setNote('');setEvidenceConfirmed(false)}}>Cancel</button>
      </div>
      <p className="muted">This decision never releases funds, enables new paid work, or changes a membership plan.</p>
    </div>}
  </section>
}
