import { useEffect, useState } from 'react'
import type { SupabaseClient } from '@supabase/supabase-js'
import { adminApi } from '../lib/admin-api'

type Row = Record<string, unknown>
type Group = { title: string; rows: Row[] }
const text = (value: unknown) => value == null ? '—' : typeof value === 'object' ? JSON.stringify(value) : String(value)

export default function OperationalModule({ client, section }: { client: SupabaseClient; section: string }) {
  const [groups, setGroups] = useState<Group[]>([])
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  useEffect(() => {
    let active = true
    setBusy(true); setError(''); setGroups([])
    const load = async () => {
      try {
        let next: Group[]
        if (section === 'opportunities') {
          const [employers, opportunities] = await Promise.all([adminApi(client, 'employers.list'), adminApi(client, 'opportunities.list')])
          next = [{ title: 'Employer registrations', rows: employers.data }, { title: 'Opportunities', rows: opportunities.data }]
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
  }, [client, section])

  return <section className="panel">
    <p>Live operational records. Results are limited to the latest records returned by the server.</p>
    {busy && <p role="status">Loading records…</p>}
    {error && <div className="error" role="alert">{error}</div>}
    {groups.map(group => <section key={group.title}><h2>{group.title}</h2>
      <div className="table-wrap"><table><thead><tr><th>Record</th><th>Status</th><th>Details</th></tr></thead>
        <tbody>{group.rows.map((row, index) => <tr key={text(row.id ?? row.feature_key ?? index)}>
          <td><strong>{text(row.title ?? row.company_name ?? row.feature_key ?? row.tx_ref ?? row.payout_ref ?? row.id)}</strong></td>
          <td>{text(row.status ?? row.moderation_status ?? row.enabled)}</td>
          <td><details><summary>Inspect record</summary><dl>{Object.entries(row).map(([key, value]) => <div key={key}><dt>{key.replaceAll('_', ' ')}</dt><dd style={{ overflowWrap: 'anywhere' }}>{text(value)}</dd></div>)}</dl></details></td>
        </tr>)}{!group.rows.length && <tr><td colSpan={3}>No records.</td></tr>}</tbody>
      </table></div>
    </section>)}
  </section>
}
