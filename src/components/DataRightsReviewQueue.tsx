import { useEffect, useState } from 'react'
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
}

const validRequestTypes = new Set(['access', 'export', 'rectification', 'erasure', 'objection', 'restriction'])

/** Read-only queue for active MFA-verified super administrators.
 * Database RLS in public.data_subject_requests is authoritative.
 * No deletion, fulfillment or user status change is performed here.
 */
export default function DataRightsReviewQueue({ client }: { client: SupabaseClient }) {
  const [rows, setRows] = useState<PrivacyRequest[]>([])
  const [loading, setLoading] = useState(true)
  const [revision, setRevision] = useState(0)
  const [error, setError] = useState('')
  const [selectedId, setSelectedId] = useState<string | null>(null)

  useEffect(() => {
    let active = true
    setLoading(true)
    setError('')
    setRows([])
    setSelectedId(null)
    void (async () => {
      try {
        const { data: assurance, error: assuranceError } = await client.auth.mfa.getAuthenticatorAssuranceLevel()
        if (assuranceError) throw assuranceError
        if (assurance?.currentLevel !== 'aal2') throw new Error('Authenticator verification is required to view privacy requests.')
        const { data, error: readError } = await client
          .from('data_subject_requests')
          .select('id,user_id,request_type,status,requested_at,updated_at,details,response_notes')
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
  // The 14-day alert is an internal operating threshold, not a statutory response deadline.
  const attention = rows.filter(row => {
    const date = Date.parse(row.requested_at)
    return Number.isFinite(date) && Date.now() - date > 14 * 24 * 60 * 60 * 1000
  }).length

  return <section className="panel" aria-label="Privacy rights administrative review queue">
    <div className="module-head">
      <div>
        <h2>Personal-data rights requests</h2>
        <p>Super administrator + verified MFA only. Review the oldest pending requests first. The database restricts access independently of this screen.</p>
      </div>
      <button type="button" disabled={loading} onClick={() => setRevision(value => value + 1)}>Refresh privacy queue</button>
    </div>
    <p className="muted">Read-only queue: this screen cannot approve, export, delete, reject, or resolve a request. Sensitive decisions require verified identity, a lawful retention check, a logged rationale and an approved administrative workflow.</p>
    <p><a href="https://github.com/Melakulms/Mela-central-dashboard-/blob/main/docs/legal/PRIVACY_REQUEST_REVIEW_RUNBOOK_2026-11-03.md" target="_blank" rel="noopener noreferrer">Open the draft privacy-request review procedure</a></p>
    {loading && <p role="status">Loading private requests…</p>}
    {error && <div className="error" role="alert">{error} <button type="button" disabled={loading} onClick={() => setRevision(value => value + 1)}>Retry privacy queue</button></div>}
    {!loading && !error && <>
      <p role="status">Showing {rows.length}{rows.length === 100 ? ' (limited to 100 oldest active requests)' : ''} active request(s): {pending} pending, {reviewing} in review. {attention} older than 14 days (internal monitoring threshold, not a legal deadline).</p>
      <div className="table-wrap">
        <table><thead><tr><th>Requested</th><th>Category</th><th>Status</th><th>Reference</th><th>Details</th></tr></thead>
          <tbody>
            {rows.map(row => <tr key={row.id}>
              <td>{new Date(row.requested_at).toLocaleDateString()}</td>
              <td>{validRequestTypes.has(row.request_type) ? row.request_type.replaceAll('_', ' ') : 'other request'}</td>
              <td>{row.status.replaceAll('_', ' ')}</td>
              <td>Request {row.id.slice(0, 8)}…</td>
              <td><button type="button" aria-label={`Inspect privacy request ${row.id.slice(0, 8)}`} onClick={() => setSelectedId(row.id)}>Inspect</button></td>
            </tr>)}
            {rows.length === 0 && <tr><td colSpan={5}>No pending or in-review privacy requests were returned.</td></tr>}
          </tbody>
        </table>
      </div>
    </>}
    {selected && <section className="detail-card" aria-label="Selected privacy request">
      <h3>Request review information</h3>
      <p>Request reference: {selected.id}</p>
      <p>User reference: {selected.user_id.slice(0, 8)}… (private; verify identity separately)</p>
      <p>Category: {validRequestTypes.has(selected.request_type) ? selected.request_type : 'other'} · Status: {selected.status}</p>
      <p>Last updated: {new Date(selected.updated_at).toLocaleString()}</p>
      <h4>Information submitted by requester</h4>
      <pre style={{ whiteSpace: 'pre-wrap', overflowWrap: 'anywhere' }}>{selected.details || 'No additional details submitted.'}</pre>
      {selected.response_notes && <><h4>Existing case notes</h4><pre style={{ whiteSpace: 'pre-wrap', overflowWrap: 'anywhere' }}>{selected.response_notes}</pre></>}
      <p className="muted">Do not copy personal data into public tickets or chats. The record cannot be modified from this inspection panel.</p>
      <button type="button" onClick={() => setSelectedId(null)}>Close request details</button>
    </section>}
  </section>
}
