import { useEffect, useRef, useState } from 'react'
import type { SupabaseClient } from '@supabase/supabase-js'

type Candidate = {
  id: string
  applicant_id: string
  headline: string
  expertise: string[]
  background: string
  review_notes: string | null
  reviewed_at: string | null
}

export default function MentorshipFinalReviewPanel({ client }: { client: SupabaseClient }) {
  const [candidates, setCandidates] = useState<Candidate[]>([])
  const [verifiedIds, setVerifiedIds] = useState<Set<string>>(new Set())
  const [selected, setSelected] = useState<Candidate | null>(null)
  const [credentials, setCredentials] = useState(false)
  const [safeguarding, setSafeguarding] = useState(false)
  const [notes, setNotes] = useState('')
  const [busy, setBusy] = useState(false)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  const [revision, setRevision] = useState(0)
  const lock = useRef(false)

  useEffect(() => {
    let active = true
    setLoading(true); setError('')
    void (async () => {
      try {
        const { data, error: readError } = await client.from('mentorship_applications')
          .select('id,applicant_id,headline,expertise,background,review_notes,reviewed_at')
          .eq('status','reviewed_eligible').order('reviewed_at',{ascending:false}).limit(100)
        if (readError) throw new Error(readError.message)
        const eligible = (data ?? []) as Candidate[]
        const ids = eligible.map((candidate) => candidate.applicant_id)
        let verified = new Set<string>()
        if (ids.length) {
          const { data: mentors, error: mentorError } = await client.from('mentor_profiles')
            .select('user_id').in('user_id',ids).eq('verified',true)
          if (mentorError) throw new Error(mentorError.message)
          verified = new Set((mentors ?? []).map((row) => row.user_id))
        }
        if (active) {setCandidates(eligible);setVerifiedIds(verified)}
      } catch (cause) {
        if (active) setError(cause instanceof Error ? cause.message : 'Could not load final mentor reviews.')
      } finally { if (active) setLoading(false) }
    })()
    return () => {active=false}
  }, [client,revision])

  const completeReview = async (event: React.FormEvent) => {
    event.preventDefault()
    if (!selected || lock.current || !credentials || !safeguarding ||
      notes.trim().length<50 || notes.trim().length>2000) return
    lock.current=true;setBusy(true);setError('');setNotice('')
    try {
      const { data: auth, error: authError } = await client.auth.getUser()
      if (authError) throw authError
      if (!auth.user) throw new Error('Administrator MFA sign-in is required.')
      const { error: rpcError } = await client.rpc('finalize_mentorship_verification',{
        p_application_id:selected.id,
        p_credential_reviewed:true,
        p_safeguarding_reviewed:true,
        p_review_notes:notes.trim(),
      })
      if (rpcError) throw new Error(rpcError.message)
      setNotice('Independently verified mentor profile activated. Decision and evidence summary have been audited.')
      setSelected(null);setCredentials(false);setSafeguarding(false);setNotes('')
      setRevision((n)=>n+1)
    } catch (cause) {
      setError(cause instanceof Error?cause.message:'Final mentor verification failed.')
    } finally {lock.current=false;setBusy(false)}
  }

  return <section className="panel" aria-label="Final mentor credential verification">
    <h2>Final mentor credential verification</h2>
    <p>Only applicants already marked eligible appear here. The database additionally requires a previously verified credential, education, professional experience or teacher record. You must actually review qualification evidence and safeguarding before confirming. Do not certify self-reported statements.</p>
    <button type="button" onClick={()=>setRevision(n=>n+1)} disabled={loading||busy}>Refresh final-verification queue</button>
    {notice&&<p role="status">{notice}</p>}
    {error&&<div role="alert" className="error">{error}</div>}
    {loading?<p role="status">Loading eligible candidates…</p> : candidates.length===0
      ? <p>No eligible candidates awaiting final credential review.</p>
      : <div className="table-wrap"><table>
        <thead><tr><th>Candidate</th><th>Earlier eligibility decision</th><th>Credential status</th><th>Review</th></tr></thead>
        <tbody>{candidates.map(row=><tr key={row.id}>
          <td><strong>{row.headline}</strong><small>{(row.expertise??[]).join(', ')}</small>
            <details><summary>Self-reported background</summary><p>{row.background}</p></details>
          </td>
          <td>{row.review_notes || 'Eligibility review recorded'}<small>{row.reviewed_at?new Date(row.reviewed_at).toLocaleDateString():''}</small></td>
          <td>{verifiedIds.has(row.applicant_id)?'Verified mentor profile':'Not verified'}</td>
          <td>{verifiedIds.has(row.applicant_id)?'Completed':<button disabled={busy} onClick={()=>{
            setSelected(row);setCredentials(false);setSafeguarding(false);setNotes('');setError('')
          }}>Verify credentials</button>}</td>
        </tr>)}</tbody>
      </table></div>}

    {selected&&<form onSubmit={completeReview} className="panel">
      <h3>Final review: {selected.headline}</h3>
      <p>Before approving, inspect the existing verified qualification or document evidence and record your evidence source, independent verification method and safeguarding outcome. No private document numbers or uploaded secrets belong in this text field.</p>
      <label><input type="checkbox" checked={credentials} disabled={busy} onChange={event=>setCredentials(event.target.checked)}/> I inspected independently verified professional, education or teacher credentials.</label>
      <label><input type="checkbox" checked={safeguarding} disabled={busy} onChange={event=>setSafeguarding(event.target.checked)}/> I performed and documented the required safeguarding review.</label>
      <label>Evidence reference, verification method and safeguarding outcome
        <textarea required rows={5} minLength={50} maxLength={2000} value={notes}
          disabled={busy} onChange={event=>setNotes(event.target.value)}
          placeholder="State the reviewed evidence, issuer confirmation method and safeguarding decision. Do not include identity numbers."/>
      </label>
      <button disabled={busy||!credentials||!safeguarding||notes.trim().length<50}>
        {busy?'Verifying…':'Complete final mentor verification'}
      </button>
      <button type="button" disabled={busy} onClick={()=>setSelected(null)}>Cancel</button>
    </form>}
  </section>
}
