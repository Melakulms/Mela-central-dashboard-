import { useEffect, useState } from 'react'
import type { SupabaseClient } from '@supabase/supabase-js'
import { adminApi } from '../lib/admin-api'
import { decisionFor } from '../lib/operational-decisions'

type Row = Record<string, unknown>
type Group = { title: string; rows: Row[] }
const text = (value: unknown) => value == null ? '—' : typeof value === 'object' ? JSON.stringify(value) : String(value)

export default function OperationalModule({ client, section, permissions }: { client: SupabaseClient; section: string; permissions: string[] }) {
  const [groups, setGroups] = useState<Group[]>([])
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [revision, setRevision] = useState(0)
  const [editing, setEditing] = useState<{group:string;row:Row}|null>(null)
  const [decision, setDecision] = useState('')
  const [notes, setNotes] = useState('')
  const [saving, setSaving] = useState(false)
  const [success, setSuccess] = useState('')

  useEffect(() => {
    let active = true
    setBusy(true); setError(''); setGroups([])
    const load = async () => {
      try {
        let next: Group[]
        if (section === 'opportunities') {
          const [employers, accounts, opportunities] = await Promise.all([adminApi(client, 'employers.list'), adminApi(client, 'employers.accounts'), adminApi(client, 'opportunities.list')])
          next = [{ title: 'Employer registrations', rows: employers.data }, {title:'Employer accounts',rows:accounts.data}, { title: 'Opportunities', rows: opportunities.data }]
        } else if (section === 'payments') {
          const [payments, payouts] = await Promise.all([adminApi(client, 'payments.list'), adminApi(client, 'payouts.list')])
          next = [{ title: 'Payments', rows: payments.data }, { title: 'Payout requests', rows: payouts.data }]
        } else if (section === 'moderation') {
          const result = await adminApi(client, 'moderation.list')
          next = [{ title: 'Reports', rows: result.reports }, { title: 'Arena integrity events', rows: result.integrity_events }, { title: 'Flagged opportunities', rows: result.flagged_opportunities }]
        } else if (section === 'settings') {
          const result = await adminApi(client, 'settings.flags')
          next = [{ title: 'Platform feature flags', rows: result.data }]
        } else {
          throw new Error('Dispute operations require a dedicated, audited workflow before this module can be enabled.')
        }
        if (active) setGroups(next.map(group => ({ ...group, rows: Array.isArray(group.rows) ? group.rows : [] })))
      } catch (error) {
        if (active) setError(error instanceof Error ? error.message : 'Could not load operational data.')
      } finally { if (active) setBusy(false) }
    }
    void load()
    return () => { active = false }
  }, [client, section, revision])

  const submitDecision = async (event: React.FormEvent) => {
    event.preventDefault()
    if (!editing || saving) return
    const spec = decisionFor(editing.group, editing.row, permissions)
    if (!spec || !spec.choices.includes(decision) || !notes.trim()) return
    setSaving(true); setError(''); setSuccess('')
    try {
      await adminApi(client, spec.action, { [spec.idField]:editing.row.id, [spec.statusField]:decision, [spec.notesField]:notes.trim(), expected_updated_at:editing.row.updated_at })
      setEditing(null); setSuccess('Decision saved and audited.'); setRevision(value => value + 1)
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'Decision could not be saved.') }
    finally { setSaving(false) }
  }

  return <section className="panel">
    <p>Live operational records. Results are limited to the latest records returned by the server.</p>
    <button onClick={() => setRevision(value => value + 1)} disabled={busy || saving}>Refresh records</button>
    {success && <p role="status">{success}</p>}
    {busy && <p role="status">Loading records…</p>}
    {error && <div className="error" role="alert">{error}</div>}
    {editing && <form onSubmit={submitDecision} className="panel" aria-label="Review decision">
      <h2>Review {text(editing.row.title ?? editing.row.company_name ?? editing.row.id)}</h2>
      <p>Registration approval creates an employer account. Company verification is a separate step. Opportunity visibility also requires a verified source and a valid deadline.</p>
      <label>Decision<select value={decision} onChange={event => setDecision(event.target.value)} disabled={saving} required>
        <option value="">Choose a decision</option>
        {decisionFor(editing.group,editing.row,permissions)?.choices.map(choice => <option key={choice} value={choice}>{choice.replaceAll('_',' ')}</option>)}
      </select></label>
      <label>Reason<textarea value={notes} onChange={event => setNotes(event.target.value)} disabled={saving} required maxLength={2000}/></label>
      <button type="submit" disabled={saving || !decision || !notes.trim()}>{saving ? 'Saving…' : 'Save decision'}</button>
      <button type="button" disabled={saving} onClick={() => setEditing(null)}>Cancel</button>
    </form>}
    {groups.map(group => <section key={group.title}><h2>{group.title}</h2>
      <div className="table-wrap"><table><thead><tr><th>Record</th><th>Status</th><th>Details</th><th>Actions</th></tr></thead>
        <tbody>{group.rows.map((row, index) => <tr key={text(row.id ?? row.feature_key ?? index)}>
          <td><strong>{text(row.title ?? row.company_name ?? row.feature_key ?? row.tx_ref ?? row.payout_ref ?? row.id)}</strong></td>
          <td>{text(row.verification_status ?? row.moderation_status ?? row.status ?? row.enabled)}</td>
          <td><details><summary>Inspect record</summary><dl>{Object.entries(row).map(([key, value]) => <div key={key}><dt>{key.replaceAll('_', ' ')}</dt><dd style={{ overflowWrap: 'anywhere' }}>{text(value)}</dd></div>)}</dl></details></td>
          <td>{decisionFor(group.title,row,permissions) && <button disabled={saving || busy} onClick={() => {setEditing({group:group.title,row});setDecision('');setNotes('');setError('');setSuccess('')}}>Review</button>}</td>
        </tr>)}{!group.rows.length && <tr><td colSpan={4}>No records.</td></tr>}</tbody>
      </table></div>
    </section>)}
  </section>
}
