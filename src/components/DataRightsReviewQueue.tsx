import { lazy, Suspense, useEffect, useRef, useState, type FormEvent } from 'react'
const PrivacyReviewCheckpointPanel = lazy(() => import('./PrivacyReviewCheckpointPanel'))
import type { SupabaseClient } from '@supabase/supabase-js'

type PrivacyRequest = {
  id: string
  user_id: string
  request_type: string
  status: 'pending' | 'in_review'
  requested_at: string
  updated_at: string
  details: string | null
  response_notes: string | null
  handled_by: string | null
}
const validRequestTypes = new Set(['access', 'export', 'rectification', 'erasure', 'objection', 'restriction'])

/** RLS and the audited BEFORE UPDATE trigger enforce MFA, role and case assignment.
 * Admin can begin or update an active review; final decision is not available.
 */
export default function DataRightsReviewQueue({ client }: { client: SupabaseClient }) {
  const [rows, setRows] = useState<PrivacyRequest[]>([])
  const [loading, setLoading] = useState(true)
  const [revision, setRevision] = useState(0)
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [publicNote, setPublicNote] = useState('')
  const [confirmed, setConfirmed] = useState(false)
  const [saving, setSaving] = useState(false)
  const saveLock = useRef(false)

  useEffect(() => {
    let active = true
    setLoading(true)
    setError('')
    setRows([])
    setSelectedId(null)
    setPublicNote('')
    setConfirmed(false)
    void (async () => {
      try {
        const { data: assurance, error: assuranceError } = await client.auth.mfa.getAuthenticatorAssuranceLevel()
        if (assuranceError) throw assuranceError
        if (assurance?.currentLevel !== 'aal2') throw new Error('Authenticator verification is required to view privacy requests.')
        const { data, error: readError } = await client
          .from('data_subject_requests')
          .select('id,user_id,request_type,status,requested_at,updated_at,details,response_notes,handled_by')
          .in('status', ['pending', 'in_review'])
          .order('requested_at', { ascending: true })
          .limit(100)
        if (readError) throw readError
        if (active) setRows((data ?? []) as PrivacyRequest[])
      } catch (cause) {
        if (active) setError(cause instanceof Error ? cause.message : 'The privacy request queue is unavailable.')
      } finally {
        if (active) setLoading(false)
      }
    })()
    return () => { active = false }
  }, [client, revision])

  const pending = rows.filter(row => row.status === 'pending').length
  const reviewing = rows.filter(row => row.status === 'in_review').length
  const selected = rows.find(row => row.id === selectedId) ?? null
  // Internal attention threshold, not a representation of the legal deadline.
  const attention = rows.filter(row => {
    const date = Date.parse(row.requested_at)
    return Number.isFinite(date) && Date.now() - date > 14 * 24 * 60 * 60 * 1000
  }).length

  async function saveReviewMessage(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (saveLock.current || saving || !confirmed || !selected ||
        (selected.status !== 'pending' && selected.status !== 'in_review') ||
        publicNote.trim().length < 12 || publicNote.trim().length > 500 ||
        (selected.status === 'in_review' && publicNote.trim() === (selected.response_notes ?? '').trim())) return
    saveLock.current = true
    setSaving(true)
    setError('')
    setSuccess('')
    try {
      const { data: assurance, error: assuranceError } = await client.auth.mfa.getAuthenticatorAssuranceLevel()
      if (assuranceError) throw assuranceError
      if (assurance?.currentLevel !== 'aal2') throw new Error('Authenticator verification expired. Please sign in and verify again.')
      const starting = selected.status === 'pending'
      const patch = starting
        ? { status: 'in_review', response_notes: publicNote.trim() }
        : { response_notes: publicNote.trim() }
      const { data, error: writeError } = await client.from('data_subject_requests')
        .update(patch)
        .eq('id', selected.id)
        .eq('status', selected.status)
        .eq('updated_at', selected.updated_at)
        .select('id,status')
        .maybeSingle()
      if (writeError) throw writeError
      if (!data) throw new Error('This request changed or was cancelled. Refresh before retrying.')
      setSuccess(starting
        ? 'Review started and recorded. The case remains open; no personal information was deleted or exported.'
        : 'Follow-up message recorded for the requester. The case remains under review; no records were deleted or exported.')
      setRevision(value => value + 1)
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Could not start the review.')
    } finally {
      saveLock.current = false
      setSaving(false)
    }
  }

  return <section className="panel" aria-label="Privacy rights administrative review queue">
    <div className="module-head">
      <div>
        <h2>Personal-data rights requests</h2>
        <p>Super administrator + verified MFA only. Review the oldest pending requests first. Database RLS enforces access independently of this screen.</p>
      </div>
      <button type="button" disabled={loading || saving} onClick={() => setRevision(value => value + 1)}>Refresh privacy queue</button>
    </div>
    <p className="muted">This screen can begin a review or send a follow-up message from the assigned reviewer, with MFA and database audit logging. It cannot approve, export, delete, reject or complete a request. Identity verification and legal-retention checks remain required.</p>
    <p><a href="https://github.com/Melakulms/Mela-central-dashboard-/blob/main/docs/legal/PRIVACY_REQUEST_REVIEW_RUNBOOK_2026-11-03.md" target="_blank" rel="noopener noreferrer">Open the draft privacy-request review procedure</a></p>
    {success && <p role="status">{success}</p>}
    {loading && <p role="status">Loading private requests…</p>}
    {error && <div className="error" role="alert">{error} <button type="button" disabled={loading || saving} onClick={() => setRevision(value => value + 1)}>Retry privacy queue</button></div>}
    {!loading && !error && <>
      <p role="status">Showing {rows.length}{rows.length === 100 ? ' (limited to 100 oldest active requests)' : ''} active request(s): {pending} pending, {reviewing} in review. {attention} older than 14 days (internal monitoring threshold, not a legal deadline).</p>
      <div className="table-wrap"><table><thead><tr><th>Requested</th><th>Category</th><th>Status</th><th>Reference</th><th>Details</th></tr></thead>
        <tbody>
          {rows.map(row => <tr key={row.id}>
            <td>{new Date(row.requested_at).toLocaleDateString()}</td>
            <td>{validRequestTypes.has(row.request_type) ? row.request_type.replaceAll('_', ' ') : 'other request'}</td>
            <td>{row.status.replaceAll('_', ' ')}</td>
            <td>Request {row.id.slice(0, 8)}…</td>
            <td><button type="button" disabled={saving} aria-label={'Inspect privacy request ' + row.id.slice(0, 8)}
              onClick={() => {setSelectedId(row.id);setPublicNote('');setConfirmed(false);setError('')}}>Inspect</button></td>
          </tr>)}
          {rows.length === 0 && <tr><td colSpan={5}>No pending or in-review privacy requests were returned.</td></tr>}
        </tbody>
      </table></div>
    </>}
    {selected && <section className="detail-card" aria-label="Selected privacy request">
      <h3>Request review information</h3>
      <p>Request reference: {selected.id}</p>
      <p>User reference: {selected.user_id.slice(0, 8)}… (private; verify identity separately)</p>
      <p>Category: {validRequestTypes.has(selected.request_type) ? selected.request_type : 'other'} · Status: {selected.status}</p>
      <p>Last updated: {new Date(selected.updated_at).toLocaleString()}</p>
      <h4>Information submitted by requester</h4>
      <pre style={{ whiteSpace: 'pre-wrap', overflowWrap: 'anywhere' }}>{selected.details || 'No additional details submitted.'}</pre>
      {selected.response_notes && <><h4>Message on record</h4><pre style={{ whiteSpace: 'pre-wrap', overflowWrap: 'anywhere' }}>{selected.response_notes}</pre></>}
      <p className="muted">Do not copy personal data into public tickets or chats. Beginning review does not fulfill this request.</p>
      {(selected.status === 'pending' || selected.status === 'in_review') && <form onSubmit={event => void saveReviewMessage(event)}>
        <h4>{selected.status === 'pending' ? 'Begin administrative review' : 'Update the requester on review progress'}</h4>
        <label htmlFor="privacy-review-public-note">Message to requester (12–500 characters)
          <textarea id="privacy-review-public-note" value={publicNote}
            onChange={event => setPublicNote(event.target.value)}
            minLength={12} maxLength={500} required disabled={saving}
            placeholder="Your request is being reviewed. We may need to verify your identity before taking action." />
        </label>
        <p className="muted">This message is visible to the requester. An update replaces the previous visible message; the audit retains a SHA-256 fingerprint of each message change, not the message text. Only the assigned MFA-verified reviewer may update an in-review case. Do not include identity documents, confidential findings or third-party information.</p>
        <label><input type="checkbox" checked={confirmed}
          onChange={event => setConfirmed(event.target.checked)} disabled={saving} />
          {' '}{selected.status === 'pending'
            ? 'I am authorized to begin review. I understand this does not fulfill or reject the request, and my action is audited.'
            : 'I am the assigned reviewer. I understand this updates the user-visible message, keeps the case open, and is audited.'}
        </label>
        <button type="submit" disabled={saving || !confirmed || publicNote.trim().length < 12 || publicNote.trim().length > 500 || (selected.status === 'in_review' && publicNote.trim() === (selected.response_notes ?? '').trim())}>
          {saving ? 'Recording review…' : selected.status === 'pending' ? 'Begin review (audited)' : 'Send review update (audited)'}
        </button>
      </form>}
      {selected.status === 'in_review' && <Suspense fallback={<p role="status">Loading restricted review checkpoints…</p>}>
        <PrivacyReviewCheckpointPanel client={client} requestId={selected.id} requestType={selected.request_type} assignedReviewerId={selected.handled_by} />
      </Suspense>}
      <button type="button" disabled={saving} onClick={() => {setSelectedId(null);setPublicNote('');setConfirmed(false)}}>Close request details</button>
    </section>}
  </section>
}
