import { useEffect, useState } from 'react'
import type { SupabaseClient } from '@supabase/supabase-js'

type Relationship = {
  id: string
  learner_id: string
  guardian_email: string
  relationship: string
  status: 'pending' | 'verified' | 'rejected' | 'revoked'
  requested_at: string
}
type Decision = 'verified' | 'rejected' | 'revoked'
export default function GuardianVerificationPanel({ client }: { client: SupabaseClient }) {
  const [rows, setRows] = useState<Relationship[]>([])
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')
  const [notes, setNotes] = useState<Record<string, string>>({})
  const [attested, setAttested] = useState<Record<string, boolean>>({})
  const [tab, setTab] = useState<'pending' | 'verified'>('pending')
  const [revision, setRevision] = useState(0)
  useEffect(() => {
    let active = true
    setLoading(true); setError('')
    void (async () => {
      try {
        const { data: assurance, error: mfaError } = await client.auth.mfa.getAuthenticatorAssuranceLevel()
        if (mfaError) throw mfaError
        if (assurance?.currentLevel !== 'aal2') throw new Error('Verified authenticator MFA is required')
        const { data, error: queryError } = await client.from('guardian_relationships')
          .select('id,learner_id,guardian_email,relationship,status,requested_at')
          .in('status', ['pending', 'verified']).order('requested_at', { ascending: false }).limit(100)
        if (queryError) throw queryError
        if (active) setRows((data ?? []) as Relationship[])
      } catch (cause) {
        if (active) setError(cause instanceof Error ? cause.message : 'Unable to load guardian approvals.')
      } finally { if (active) setLoading(false) }
    })()
    return () => { active = false }
  }, [client, revision])
  const decide = async (row: Relationship, decision: Decision) => {
    if (busy) return
    const note = (notes[row.id] ?? '').trim()
    if (decision === 'verified' && (note.length < 12 || !attested[row.id])) {
      setError('Review the parent relationship independently, record the evidence, and confirm the check before verification.')
      return
    }
    if ((decision === 'revoked' || decision === 'rejected') && note.length < 12) {
      setError('A review decision reason of at least 12 characters is required.')
      return
    }
    setBusy(true); setError(''); setSuccess('')
    try {
      const { error: callError } = await client.rpc('review_guardian_consent', {
        p_relationship_id: row.id, p_decision: decision, p_notes: note || null,
      })
      if (callError) throw callError
      setSuccess('Guardian relationship ' + decision + '. The decision is stored in staging.')
      setNotes(old => ({ ...old, [row.id]: '' }))
      setAttested(old => ({ ...old, [row.id]: false }))
      setRevision(v => v + 1)
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Guardian review failed; no approval was recorded.')
    } finally { setBusy(false) }
  }
  const visible = rows.filter(r => r.status === tab)
  return <section className="panel" aria-label="Guardian verification">
    <div className="module-head"><div><h2>Guardian relationship verification — staging</h2>
      <p>Only an active super-admin with current MFA may record or revoke a verified guardian relationship. Do not approve solely because an email was supplied.</p>
    </div><button className="refresh" disabled={loading || busy} onClick={() => setRevision(v => v + 1)}>Refresh</button></div>
    <div className="toolbar"><button className={tab === 'pending' ? '' : 'secondary'} onClick={() => setTab('pending')}>Pending</button>
      <button className={tab === 'verified' ? '' : 'secondary'} onClick={() => setTab('verified')}>Verified / revoke</button></div>
    {error && <div className="error" role="alert">{error}</div>}
    {success && <p role="status">{success}</p>}
    {loading ? <p role="status">Checking guardian queue…</p> :
      visible.length === 0 ? <p className="muted">No {tab} relationships. No test accounts are created by this screen.</p> :
      visible.map(r => <div className="detail-card" key={r.id}>
        <h3>{r.relationship} · {r.status}</h3>
        <p><strong>Guardian email:</strong> {r.guardian_email}</p>
        <p><strong>Learner account:</strong> {r.learner_id}</p>
        <p className="muted">Requested {new Date(r.requested_at).toLocaleString()}</p>
        <label htmlFor={'guardian-note-' + r.id}>Administrator review notes</label>
        <textarea id={'guardian-note-' + r.id} value={notes[r.id] ?? ''}
          maxLength={1000} placeholder="Record how the adult identity, parent relationship, consent and account ownership were verified."
          onChange={e => setNotes(old => ({ ...old, [r.id]: e.target.value }))}/>
        {r.status === 'pending' && <label style={{ display: 'flex', gap: 8 }}>
          <input type="checkbox" checked={Boolean(attested[r.id])}
            onChange={e => setAttested(old => ({ ...old, [r.id]: e.target.checked }))}/>
          I independently checked the guardian's identity, relationship, account and consent.
        </label>}
        <div className="toolbar">
          {r.status === 'pending' ? <>
            <button disabled={busy || !attested[r.id] || (notes[r.id] ?? '').trim().length < 12}
              onClick={() => void decide(r, 'verified')}>Verify guardian</button>
            <button className="danger-btn" disabled={busy || (notes[r.id] ?? '').trim().length < 12} onClick={() => void decide(r, 'rejected')}>Reject request</button>
          </> : <button className="danger-btn" disabled={busy || (notes[r.id] ?? '').trim().length < 12}
            onClick={() => void decide(r, 'revoked')}>Revoke verification</button>}
        </div>
      </div>)}
    <p className="muted">Rejection and revocation are recorded server-side. A newly registered parent must verify their email before a pending request can be approved. Personal documents should stay in an authorized review process, not this form.</p>
  </section>
}
