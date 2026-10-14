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
  const [teacherCodes, setTeacherCodes] = useState<string[]>([])
  const [teacherBatchCount, setTeacherBatchCount] = useState(5)
  const [batchCopied, setBatchCopied] = useState(false)

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

  // Deliberately use the existing authenticated, permission-checked, MFA-gated
  // invite.create API for each code. No direct database write or privileged
  // browser credentials are used. A partial batch keeps all issued codes visible.
  const createTeacherBatch = async () => {
    if (busy) return
    setBusy(true)
    setError('')
    setTeacherCodes([])
    setBatchCopied(false)
    const created: string[] = []
    try {
      const count = Math.min(Math.max(teacherBatchCount, 1), 20)
      for (let index = 0; index < count; index++) {
        const result = await betaAdminApi(client, 'invite.create', {
          role: 'teacher',
          expires_in_days: days,
          note: note.trim() || 'Teacher review onboarding',
        })
        const code = result.data?.access_code
        if (typeof code !== 'string' || !code.startsWith('MELA-B-')) {
          throw new Error('The server did not return the one-time code. Contact support before continuing.')
        }
        created.push(code)
        setTeacherCodes([...created])
      }
      setNote('')
      await load()
    } catch (err) {
      setError(`${created.length} teacher codes were generated before this error: ${err instanceof Error ? err.message : 'Unable to create teacher invites.'} Save the displayed codes before leaving this screen.`)
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
          <p><a href="https://melakulms.github.io/mela-app/?signup=invite" target="_blank" rel="noopener noreferrer">Open the MELA invitation registration page</a> · Share this page with a tester and privately provide their one-time code.</p>
          <p>Create one-time access codes for the zero-budget closed beta. New users choose Student, Family, Teacher, or Employer in the registration screen. Their selection must match this one-time invitation. Account type is never granted by changing a browser field; teachers and employers still need verification.</p>
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

      <div className="toolbar" aria-label="Verified teacher invitation batch">
        <div>
          <strong>Invite subject teachers for question review</strong>
          <p className="muted">Only a signed-in authorized administrator with required MFA can generate these codes. Registration does not approve a teacher or grant question review access.</p>
        </div>
        <label>Teacher codes
          <select aria-label="Number of teacher invitation codes" value={teacherBatchCount} onChange={event => setTeacherBatchCount(Number(event.target.value))} disabled={busy}>
            <option value={5}>5</option><option value={10}>10</option><option value={20}>20</option>
          </select>
        </label>
        <button type="button" onClick={() => void createTeacherBatch()} disabled={busy}><UserPlus size={16}/> Generate teacher codes</button>
      </div>

      {teacherCodes.length > 0 && <div className="notice" role="status">
        <Check size={18}/>
        <div style={{flex:1,minWidth:0}}>
          <strong>{teacherCodes.length} one-time teacher invites generated — copy them now</strong>
          <p className="muted">Each code must be shared privately with exactly one teacher. Full codes are shown only now; refreshing the page clears this list. Never post them publicly. After signup, verify each teacher's qualifications before assigning questions.</p>
          <textarea aria-label="New teacher invitation codes" readOnly rows={Math.min(teacherCodes.length+1,12)} style={{width:'100%',maxWidth:'100%'}} value={teacherCodes.map((code,index)=>`${index+1}. ${code}`).join('\n')}/>
        </div>
        <button type="button" className="refresh" onClick={async () => {
          try { await navigator.clipboard.writeText(teacherCodes.join('\n')); setBatchCopied(true) }
          catch { setBatchCopied(false); setError('The browser could not copy the codes; select the list and copy it manually.') }
        }}><Copy size={15}/>{batchCopied ? 'Copied' : 'Copy codes'}</button>
      </div>}

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
