import { useEffect, useState } from 'react'
import type { SupabaseClient } from '@supabase/supabase-js'
import { adminApi } from '../lib/admin-api'

type Flag = {
  feature_key: string
  enabled: boolean
  maintenance_message: string | null
  updated_at?: string | null
}
const deferredFinance = /(payment|payout|escrow|finance|cash|withdraw)/i

export default function FeatureSettingsPanel({ client }: { client: SupabaseClient }) {
  const [flags, setFlags] = useState<Flag[]>([])
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  const [editing, setEditing] = useState<Flag | null>(null)
  const [enabled, setEnabled] = useState(false)
  const [message, setMessage] = useState('')
  const [reason, setReason] = useState('')

  const refresh = async () => {
    setLoading(true); setError('')
    try {
      const result = await adminApi(client, 'settings.flags')
      if (!Array.isArray(result?.data)) throw new Error('Feature settings are unavailable.')
      setFlags(result.data)
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Could not load feature settings.')
    } finally { setLoading(false) }
  }

  useEffect(() => { void refresh() }, [client])

  const openEditor = (flag: Flag) => {
    setEditing(flag); setEnabled(flag.enabled)
    setMessage(flag.maintenance_message ?? ''); setReason('')
    setError(''); setNotice('')
  }

  const save = async (event: React.FormEvent) => {
    event.preventDefault()
    if (!editing || saving || reason.trim().length < 10) return
    if (deferredFinance.test(editing.feature_key) && enabled) {
      setError('Financial features are deferred. Enabling them requires a separately approved release.')
      return
    }
    setSaving(true); setError(''); setNotice('')
    try {
      await adminApi(client, 'settings.flag.update', {
        feature_key: editing.feature_key,
        enabled,
        maintenance_message: message.trim(),
        expected_updated_at: editing.updated_at,
        change_reason: reason.trim(),
      })
      setEditing(null)
      setNotice('Feature setting saved through the audited administration API.')
      await refresh()
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Could not save. Refresh and retry.')
    } finally { setSaving(false) }
  }

  return <section className="panel" aria-label="Platform feature settings">
    <div className="module-head">
      <div>
        <h2>Platform feature controls</h2>
        <p>These are real backend feature flags. Every change requires an MFA-protected administrator session and is recorded by the server. A flag alone does not guarantee that every page or write operation is guarded.</p>
      </div>
      <button type="button" className="refresh" onClick={() => void refresh()} disabled={saving || loading}>Refresh flags</button>
    </div>
    <p className="muted">Payments, payouts and escrow remain deferred. They cannot be enabled from this screen.</p>
    {error && <div className="error" role="alert">{error}</div>}
    {notice && <p role="status">{notice}</p>}
    {loading ? <p role="status">Loading feature settings…</p> : <div className="table-wrap">
      <table>
        <thead><tr><th>Module</th><th>Status</th><th>Maintenance message</th><th>Change</th></tr></thead>
        <tbody>{flags.map(flag => <tr key={flag.feature_key}>
          <td><strong>{flag.feature_key.replaceAll('_',' ')}</strong></td>
          <td><span className={'status-pill ' + (flag.enabled ? 'approved' : 'pending')}>{flag.enabled ? 'Enabled' : 'Disabled'}</span></td>
          <td>{flag.maintenance_message || '—'}</td>
          <td><button type="button" onClick={() => openEditor(flag)} disabled={saving}>Edit</button></td>
        </tr>)}
          {flags.length === 0 && <tr><td colSpan={4}>No feature flags are available.</td></tr>}
        </tbody>
      </table>
    </div>}
    {editing && <form onSubmit={event => void save(event)} className="detail-card" aria-label="Edit feature setting">
      <h3>Change {editing.feature_key.replaceAll('_', ' ')}</h3>
      <label>Availability
        <select value={enabled ? 'on' : 'off'} onChange={e => setEnabled(e.target.value === 'on')} disabled={saving}>
          <option value="off">Disabled</option>
          <option value="on" disabled={deferredFinance.test(editing.feature_key)}>Enabled</option>
        </select>
      </label>
      <label>Maintenance explanation
        <textarea value={message} onChange={e => setMessage(e.target.value)} maxLength={500} disabled={saving} />
      </label>
      <label>Reason for this change (required for confirmation)
        <textarea value={reason} onChange={e => setReason(e.target.value)} maxLength={1000} minLength={10} required disabled={saving} />
      </label>
      <p className="muted">The server records the change and the reason in the administrator audit trail.</p>
      <button type="submit" disabled={saving || reason.trim().length < 10 || (deferredFinance.test(editing.feature_key) && enabled)}>
        {saving ? 'Saving…' : 'Confirm change'}
      </button>{' '}
      <button type="button" className="secondary" disabled={saving} onClick={() => setEditing(null)}>Cancel</button>
    </form>}
  </section>
}
