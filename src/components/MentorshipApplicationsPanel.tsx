import { useEffect, useRef, useState } from 'react'
import type { SupabaseClient } from '@supabase/supabase-js'

type Row = {
  id: string; applicant_id: string; headline: string; expertise: string[]
  languages: string[]; background: string; status: string
  submitted_at: string; review_notes: string | null
}
export default function MentorshipApplicationsPanel({ client }: { client: SupabaseClient }) {
  const [rows, setRows] = useState<Row[]>([])
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  const [loading, setLoading] = useState(true)
  const [revision, setRevision] = useState(0)
  const [busy, setBusy] = useState(false)
  const [selected, setSelected] = useState<Row | null>(null)
  const [decision, setDecision] = useState<'reviewed_eligible' | 'rejected' | ''>('')
  const [note, setNote] = useState('')
  const saveLock = useRef(false)

  useEffect(() => {
    let active = true
    setLoading(true); setError('')
    Promise.resolve(client.from('mentorship_applications')
      .select('id,applicant_id,headline,expertise,languages,background,status,submitted_at,review_notes')
      .order('submitted_at',{ ascending:false }).limit(100))
      .then(({data,error:fetchError}) => {
        if (fetchError) throw fetchError
        if (active) setRows((data ?? []) as Row[])
      }).catch((cause) => {
        if (active) setError(cause instanceof Error ? cause.message : 'Could not fetch mentor applications.')
      }).finally(() => { if (active) setLoading(false) })
    return () => { active = false }
  }, [client,revision])

  const review = async (event: React.FormEvent) => {
    event.preventDefault()
    if (saveLock.current || !selected || !decision || note.trim().length < 10) return
    saveLock.current = true; setBusy(true);setError('');setNotice('')
    try {
      const { data: auth, error: authError } = await client.auth.getUser()
      if (authError) throw authError
      if (!auth.user) throw new Error('You must sign in with an MFA-verified administrator session.')
      const { data, error:reviewError } = await client.from('mentorship_applications')
        .update({
          status: decision,
          review_notes: note.trim().slice(0,2000),
          reviewed_by: auth.user.id, reviewed_at: new Date().toISOString(),
        }).eq('id',selected.id).eq('status','pending_review').select('id')
      if (reviewError) throw reviewError
      if (!data?.length) throw new Error('This application was already reviewed or your MFA permissions are insufficient.')
      setSelected(null);setDecision('');setNote('')
      setNotice('Application review recorded. Mentor identity and qualifications still require independent verification.')
      setRevision((value) => value + 1)
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Could not review application.')
    } finally { setBusy(false);saveLock.current = false }
  }

  return <section className="panel" aria-label="Mentorship verification applications">
    <h2>Mentor application reviews</h2>
    <p>Applications are self-reported. Review eligibility and request evidence using MELA's separately controlled verification process. Marking an application eligible does <strong>not</strong> verify a mentor profile or publish it in the learner directory.</p>
    <button type="button" onClick={() => setRevision((n) => n + 1)} disabled={loading || busy}>Refresh mentor applications</button>
    {notice && <p role="status">{notice}</p>}
    {error && <div className="error" role="alert">{error}</div>}
    {loading ? <p role="status">Loading mentor application queue…</p> : rows.length === 0
      ? <p>No mentor applications to review.</p>
      : <div className="table-wrap"><table>
        <thead><tr><th>Applicant</th><th>Expertise and languages</th><th>Status</th><th>Review</th></tr></thead>
        <tbody>{rows.map((row) => <tr key={row.id}>
          <td><strong>{row.headline}</strong><small>{new Date(row.submitted_at).toLocaleDateString()}</small>
            <details><summary>Qualification statement</summary><p style={{ whiteSpace:'pre-wrap',overflowWrap:'anywhere' }}>{row.background}</p></details></td>
          <td>{(row.expertise ?? []).join(', ')}<small>{(row.languages ?? []).join(', ')}</small></td>
          <td>{row.status.replaceAll('_',' ')}</td>
          <td>{row.status === 'pending_review' ? <button disabled={busy} onClick={() => {setSelected(row);setDecision('');setNote('')}}>Review application</button>
            : <span>{row.review_notes || 'Decision saved'}</span>}</td>
        </tr>)}</tbody>
      </table></div>}
    {selected && <form className="panel" onSubmit={review}>
      <h3>Review: {selected.headline}</h3>
      <p>Only an MFA-verified administrator can save a decision. An eligible application must still undergo independent mentor identity, qualification, and safeguarding verification.</p>
      <label>Decision<select required disabled={busy} value={decision} onChange={(e) => setDecision(e.target.value as typeof decision)}>
        <option value="">Choose a decision</option>
        <option value="reviewed_eligible">Eligible for further verification</option>
        <option value="rejected">Reject application</option>
      </select></label>
      <label>Review evidence and reason<textarea required disabled={busy} rows={4} value={note} minLength={10} maxLength={2000} onChange={(e) => setNote(e.target.value)}/></label>
      <button disabled={busy || !decision || note.trim().length < 10}>{busy?'Saving…':'Record application review'}</button>
      <button type="button" disabled={busy} onClick={() => setSelected(null)}>Cancel</button>
    </form>}
  </section>
}
