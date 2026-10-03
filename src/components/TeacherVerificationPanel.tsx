import { useEffect, useRef, useState } from 'react'
import type { SupabaseClient } from '@supabase/supabase-js'

type TeacherReview = {
  user_id: string
  full_name?: string | null
  email?: string | null
  account_status?: string | null
  qualification?: string | null
  subjects_taught?: string[] | null
  grade_levels?: string[] | null
  teaching_experience_years?: number | null
  institution?: string | null
  certifications?: string[] | null
  biography?: string | null
  verification_status: 'pending' | 'approved' | 'rejected' | 'suspended'
  verification_notes?: string | null
  verified_at?: string | null
  review_authorized?: boolean
  review_subject_areas?: string[] | null
  created_at?: string | null
}

type Decision = 'approved' | 'rejected' | 'suspended'

const list = (value?: string[] | null) => value?.length ? value.join(', ') : '—'

export default function TeacherVerificationPanel({ client }: { client: SupabaseClient }) {
  const saving = useRef(false)
  const [status, setStatus] = useState('pending')
  const [rows, setRows] = useState<TeacherReview[]>([])
  const [selected, setSelected] = useState<TeacherReview | null>(null)
  const [decision, setDecision] = useState<Decision | ''>('')
  const [note, setNote] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')
  const [revision, setRevision] = useState(0)

  useEffect(() => {
    let active = true
    const load = async () => {
      setBusy(true); setError('')
      setRows([]); setSelected(null); setDecision(''); setNote('')
      try {
        const { data, error } = await client.rpc('get_teacher_verification_queue', {
          p_status: status || null,
          p_limit: 200,
        })
        if (error) throw error
        if (active) setRows(Array.isArray(data) ? data as TeacherReview[] : [])
      } catch (cause) {
        if (active) setError(cause instanceof Error ? cause.message : 'Teacher verification queue could not be loaded.')
      } finally { if (active) setBusy(false) }
    }
    void load()
    return () => { active = false }
  }, [client, status, revision])

  const begin = (row: TeacherReview) => {
    setSelected(row); setDecision(row.verification_status === 'pending' ? '' : row.verification_status); setNote(''); setError(''); setSuccess('')
  }

  const submit = async (event: React.FormEvent) => {
    event.preventDefault()
    if (saving.current || busy || !selected || !decision || note.trim().length < 5) return
    saving.current = true
    setBusy(true); setError(''); setSuccess('')
    try {
      const { error } = await client.rpc('review_teacher_profile', {
        p_user_id: selected.user_id,
        p_decision: decision,
        p_note: note.trim(),
      })
      if (error) throw error
      setSuccess(decision === 'approved'
        ? 'Teacher approved. Subject-limited educator content-review access is now active.'
        : `Teacher verification changed to ${decision}. Content-review access is disabled.`)
      setSelected(null); setDecision(''); setNote(''); setRevision(value => value + 1)
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'Teacher verification decision could not be saved.') }
    finally { saving.current = false; setBusy(false) }
  }

  return <section className="panel" aria-label="Teacher reviewer verification">
    <div className="module-head"><div><h2>Teacher reviewer verification</h2><p>Approve qualified educators for subject-limited chapter and question review. This action requires the current MFA-protected admin session and is audited.</p></div><button className="refresh" onClick={() => setRevision(value => value + 1)} disabled={busy}>Refresh</button></div>
    <p className="muted">Approval requires a qualification, institution, at least one teaching subject, and at least one grade level. Approved qualification fields are then locked against self-service edits.</p>
    <div className="toolbar"><label>Status <select value={status} onChange={event => setStatus(event.target.value)} disabled={busy}><option value="pending">Pending</option><option value="approved">Approved</option><option value="rejected">Rejected</option><option value="suspended">Suspended</option><option value="">All</option></select></label></div>
    {success && <p role="status">{success}</p>}
    {error && <div className="error" role="alert">{error}</div>}
    {selected && <form className="detail-card" onSubmit={submit} aria-label="Teacher verification decision">
      <div className="module-head"><div><h3>{selected.full_name || 'Teacher verification'}</h3><p>{selected.email || selected.user_id}</p></div><button type="button" className="icon-btn" onClick={() => setSelected(null)} disabled={busy}>×</button></div>
      <dl>
        <dt>Qualification</dt><dd>{selected.qualification || '—'}</dd>
        <dt>Institution</dt><dd>{selected.institution || '—'}</dd>
        <dt>Subjects</dt><dd>{list(selected.subjects_taught)}</dd>
        <dt>Grade levels</dt><dd>{list(selected.grade_levels)}</dd>
        <dt>Experience</dt><dd>{selected.teaching_experience_years ?? 0} years</dd>
        <dt>Certifications</dt><dd>{list(selected.certifications)}</dd>
        <dt>Biography</dt><dd>{selected.biography || '—'}</dd>
        <dt>Account status</dt><dd>{selected.account_status || '—'}</dd>
        <dt>Reviewer access</dt><dd>{selected.review_authorized ? `Active · ${list(selected.review_subject_areas)}` : 'Not active'}</dd>
        <dt>Previous verification note</dt><dd>{selected.verification_notes || '—'}</dd>
      </dl>
      <label>Decision<select value={decision} onChange={event => setDecision(event.target.value as Decision | '')} required disabled={busy}><option value="">Choose a decision</option><option value="approved">Approve teacher + review access</option><option value="rejected">Reject</option><option value="suspended">Suspend</option></select></label>
      <label>Verification note<textarea value={note} onChange={event => setNote(event.target.value)} minLength={5} maxLength={4000} required disabled={busy} placeholder="Record the qualification evidence you checked and the reason for this decision." /></label>
      <div className="toolbar"><button type="button" className="refresh" onClick={() => setSelected(null)} disabled={busy}>Cancel</button><button type="submit" disabled={busy || !decision || note.trim().length < 5}>{busy ? 'Saving…' : 'Save audited decision'}</button></div>
    </form>}
    <div className="table-wrap"><table><thead><tr><th>Teacher</th><th>Qualification</th><th>Subjects</th><th>Grades</th><th>Status</th><th>Review access</th><th/></tr></thead><tbody>
      {rows.map(row => <tr key={row.user_id}><td><strong>{row.full_name || 'Unnamed teacher'}</strong><small>{row.email || row.user_id}</small></td><td>{row.qualification || '—'}<small>{row.institution || 'No institution'}</small></td><td>{list(row.subjects_taught)}</td><td>{list(row.grade_levels)}</td><td><span className={`status-pill ${row.verification_status}`}>{row.verification_status}</span></td><td>{row.review_authorized ? 'Active' : '—'}</td><td><button className="refresh" onClick={() => begin(row)} disabled={busy}>Review</button></td></tr>)}
      {!rows.length && !busy && <tr><td colSpan={7} className="empty">No teacher profiles match this status.</td></tr>}
    </tbody></table></div>
  </section>
}
