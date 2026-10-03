import { useEffect, useState } from 'react'
import type { SupabaseClient } from '@supabase/supabase-js'
import { AlertTriangle, Check, Copy, RefreshCw, UserPlus, XCircle } from 'lucide-react'
import { betaAdminApi } from '../lib/admin-api'

type BetaRole = 'student' | 'parent' | 'teacher' | 'company'

type Invite = {
  id: string
  role: BetaRole
  expires_at: string
  used_at: string | null
  used_by: string | null
  revoked_at: string | null
  note: string | null
  created_at: string
}

export default function BetaInvitesPanel({ client }: { client: SupabaseClient }) {
  const [rows, setRows] = useState<Invite[]>([])
  const [role, setRole] = useState<BetaRole>('student')
  const [days, setDays] = useState(7)
  const [note, setNote] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [accessCode, setAccessCode] = useState('')
  const [copied, setCopied] = useState(false)

  const load = async () => {
    setBusy(true)
    setError('')
    try {
      const result = await betaAdminApi(client, 'invite.list', { limit: 50 })
      setRows(result.data ?? [])
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Unable to load beta invites.')
    } finally {
      setBusy(false)
    }
  }

  useEffect(() => { void load() }, [])

  const createInvite = async () => {
    setBusy(true)
    setError('')
    setAccessCode('')
    setCopied(false)
    try {
      const result = await betaAdminApi(client, 'invite.create', {
        role,
        expires_in_days: days,
        note: note.trim() || undefined,
      })
      setAccessCode(result.data?.access_code ?? '')
      setNote('')
      await load()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Unable to create beta invite.')
      setBusy(false)
    }
  }

  const revokeInvite = async (id: string) => {
    setBusy(true)
    setError('')
    try {
      await betaAdminApi(client, 'invite.revoke', { invite_id: id })
      await load()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Unable to revoke beta invite.')
      setBusy(false)
    }
  }

  const statusOf = (row: Invite) => {
    if (row.revoked_at) return 'revoked'
    if (row.used_at) return 'used'
    if (new Date(row.expires_at).getTime() <= Date.now()) return 'expired'
    return 'active'
  }

  return (
    <section className="panel">
      <div className="module-head">
        <div>
          <h2>Beta invites</h2>
          <p>Create one-time access codes for the zero-budget closed beta. The role is locked into the code and cannot be chosen by the learner.</p>
        </div>
        <button className="refresh" type="button" onClick={() => void load()} disabled={busy}>
          <RefreshCw size={15}/>{busy ? 'Loading' : 'Refresh'}
        </button>
      </div>

      {error && <div className="error" role="alert"><AlertTriangle size={16}/>{error}</div>}

      <div className="toolbar">
        <label>
          Role
          <select value={role} onChange={(event) => setRole(event.target.value as BetaRole)} disabled={busy}>
            <option value="student">Student</option>
            <option value="parent">Parent / Guardian</option>
            <option value="teacher">Teacher</option>
            <option value="company">Employer / Company</option>
          </select>
        </label>
        <label>
          Expires
          <select value={days} onChange={(event) => setDays(Number(event.target.value))} disabled={busy}>
            <option value={1}>1 day</option>
            <option value={3}>3 days</option>
            <option value={7}>7 days</option>
            <option value={14}>14 days</option>
            <option value={30}>30 days</option>
          </select>
        </label>
        <input
          aria-label="Invite note"
          value={note}
          maxLength={500}
          placeholder="Optional note, e.g. Addis pilot school"
          onChange={(event) => setNote(event.target.value)}
          disabled={busy}
        />
        <button type="button" onClick={() => void createInvite()} disabled={busy}>
          <UserPlus size={16}/>{busy ? 'Working…' : 'Create access code'}
        </button>
      </div>

      {accessCode && (
        <div className="notice" role="status">
          <Check size={18}/>
          <div>
            <strong>New beta access code — copy it now</strong>
            <p className="muted">For security, MELA stores only a hash. The full code cannot be displayed again.</p>
            <code>{accessCode}</code>
          </div>
          <button type="button" className="refresh" onClick={async () => {
            try { await navigator.clipboard.writeText(accessCode); setCopied(true) } catch { setCopied(false) }
          }}><Copy size={15}/>{copied ? 'Copied' : 'Copy'}</button>
        </div>
      )}

      <div className="table-wrap">
        <table>
          <thead><tr><th>Role</th><th>Status</th><th>Expires</th><th>Note</th><th>Created</th><th/></tr></thead>
          <tbody>
            {rows.map((row) => {
              const status = statusOf(row)
              return (
                <tr key={row.id}>
                  <td><span className="pill">{row.role}</span></td>
                  <td><span className={`status-pill ${status}`}>{status}</span></td>
                  <td>{new Date(row.expires_at).toLocaleString()}</td>
                  <td>{row.note || '—'}</td>
                  <td>{new Date(row.created_at).toLocaleString()}</td>
                  <td>{status === 'active' && <button className="icon-btn" type="button" title="Revoke unused invite" disabled={busy} onClick={() => void revokeInvite(row.id)}><XCircle size={17}/></button>}</td>
                </tr>
              )
            })}
            {!rows.length && !busy && <tr><td colSpan={6} className="empty">No beta invites created yet.</td></tr>}
          </tbody>
        </table>
      </div>
    </section>
  )
}
