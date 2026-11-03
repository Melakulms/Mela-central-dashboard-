import { useEffect, useRef, useState, type FormEvent } from 'react'
import type { SupabaseClient } from '@supabase/supabase-js'

type CheckpointKey =
  | 'requester_identity' | 'guardian_authority' | 'scope_and_third_parties'
  | 'retention_and_legal_basis' | 'safeguarding_review' | 'fulfillment_plan'
type Finding = 'needs_follow_up' | 'reviewed_no_issue_identified'
type CheckpointRow = {
  id: string
  checkpoint: CheckpointKey
  finding: Finding
  recorded_at: string
}

const checkpointItems: { value: CheckpointKey; label: string }[] = [
  { value: 'requester_identity', label: 'Requester identity and account ownership' },
  { value: 'guardian_authority', label: 'Guardian authority (if applicable)' },
  { value: 'scope_and_third_parties', label: 'Request scope and third-party privacy' },
  { value: 'retention_and_legal_basis', label: 'Retention requirements and legal basis' },
  { value: 'safeguarding_review', label: 'Child safeguarding and incident preservation' },
  { value: 'fulfillment_plan', label: 'Safe fulfillment plan and escalation' },
]
const findingItems: {value: Finding; label: string}[] = [
  {value: 'needs_follow_up', label: 'Requires further verification or review'},
  {value: 'reviewed_no_issue_identified', label: 'Reviewed; no issue identified at this checkpoint (not approval)'},
]
const labelFor = (value: string) => checkpointItems.find(item => item.value === value)?.label ?? value
const findingLabel = (value: string) => findingItems.find(item => item.value === value)?.label ?? value

/** Admin-only, append-only operational checklist. Database RLS + trigger require
 * assigned super_admin at AAL2 and an in_review case. Never makes a final decision.
 */
export default function PrivacyReviewCheckpoints({client, requestId}: {
  client: SupabaseClient; requestId: string
}) {
  const [entries, setEntries] = useState<CheckpointRow[]>([])
  const [checkpoint, setCheckpoint] = useState<CheckpointKey>('requester_identity')
  const [finding, setFinding] = useState<Finding>('needs_follow_up')
  const [confirmed, setConfirmed] = useState(false)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [revision, setRevision] = useState(0)
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  const lock = useRef(false)

  useEffect(() => {
    let active = true
    setEntries([])
    setLoading(true)
    setError('')
    setConfirmed(false)
    void (async () => {
      try {
        const { data: assurance, error: assuranceError } =
          await client.auth.mfa.getAuthenticatorAssuranceLevel()
        if (assuranceError) throw assuranceError
        if (assurance?.currentLevel !== 'aal2')
          throw new Error('Authenticator verification is required to inspect review checkpoints.')
        const {data, error: readError} = await client.from('privacy_review_checkpoints')
          .select('id,checkpoint,finding,recorded_at')
          .eq('request_id', requestId)
          .order('recorded_at', {ascending: false})
          .limit(50)
        if (readError) throw readError
        if (active) setEntries((data ?? []) as CheckpointRow[])
      } catch (cause) {
        if (active) setError(cause instanceof Error ? cause.message : 'Could not load review checkpoints.')
      } finally {
        if (active) setLoading(false)
      }
    })()
    return () => {active = false}
  }, [client, requestId, revision])

  async function record(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (loading || saving || !confirmed || lock.current) return
    lock.current = true
    setSaving(true)
    setError('')
    setNotice('')
    try {
      const {data: assurance, error: assuranceError} =
        await client.auth.mfa.getAuthenticatorAssuranceLevel()
      if (assuranceError) throw assuranceError
      if (assurance?.currentLevel !== 'aal2')
        throw new Error('Authenticator verification has expired. Verify again before recording.')
      const {data: auth, error: authError} = await client.auth.getUser()
      if (authError || !auth.user)
        throw new Error('Please sign in again before recording a review checkpoint.')
      const {data, error: insertError} = await client.from('privacy_review_checkpoints')
        .insert({request_id: requestId, reviewer_id: auth.user.id, checkpoint, finding})
        .select('id').maybeSingle()
      if (insertError) throw insertError
      if (!data) throw new Error('The checkpoint was not confirmed by the database. Refresh and retry.')
      setConfirmed(false)
      setNotice('Review checkpoint recorded in the restricted audit log. The case remains open; this is not a legal decision.')
      setRevision(v => v + 1)
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Checkpoint could not be recorded.')
    } finally {
      lock.current = false
      setSaving(false)
    }
  }

  return <section className="detail-card" aria-label="Private review checkpoints">
    <h4>Restricted review checklist</h4>
    <p className="muted">Only the assigned MFA-verified super administrator can record a checkpoint. Entries are append-only and cannot certify identity, guardian consent, deletion, or legal compliance. Never enter IDs, documents, names, or confidential evidence here.</p>
    {loading && <p role="status">Loading private checklist…</p>}
    {error && <p role="alert">{error}</p>}
    {notice && <p role="status">{notice}</p>}
    {!loading && !error && <>
      <p role="status">{entries.length} recent checkpoint record(s) shown{entries.length === 50 ? ' (last 50)' : ''}.</p>
      {entries.length > 0 && <ul>{entries.map(entry => <li key={entry.id}>
        {labelFor(entry.checkpoint)} — {findingLabel(entry.finding)}
        {' · '}{new Date(entry.recorded_at).toLocaleString()}
      </li>)}</ul>}
      {entries.length === 0 && <p>No review checkpoints have been recorded for this case.</p>}
      <form onSubmit={event => void record(event)}>
        <label htmlFor="privacy-checkpoint-type">Review checkpoint</label>
        <select id="privacy-checkpoint-type" value={checkpoint} disabled={saving}
          onChange={event => setCheckpoint(event.target.value as CheckpointKey)}>
          {checkpointItems.map(option => <option value={option.value} key={option.value}>{option.label}</option>)}
        </select>
        <label htmlFor="privacy-checkpoint-finding">Limited review finding</label>
        <select id="privacy-checkpoint-finding" value={finding} disabled={saving}
          onChange={event => setFinding(event.target.value as Finding)}>
          {findingItems.map(option => <option value={option.value} key={option.value}>{option.label}</option>)}
        </select>
        <label><input type="checkbox" checked={confirmed} disabled={saving}
          onChange={event => setConfirmed(event.target.checked)}/>
          {' '}I have actually checked this item. This record contains no evidence and is not final approval, export, erasure or request completion.
        </label>
        <button type="submit" disabled={saving || !confirmed}>
          {saving ? 'Recording checkpoint…' : 'Record restricted checkpoint (audited)'}
        </button>
      </form>
    </>}
  </section>
}
