import { useState } from 'react'
import type { SupabaseClient } from '@supabase/supabase-js'

type SubjectSummary = {
  program_key: string; grade_level: number | null; subject_title: string
  total: number; teacher_approved: number; needs_changes: number; remaining: number
}
type ReviewSummary = {
  active_questions: number
  teacher_approved: number
  teacher_changes_required: number
  pending_or_unverified: number
  review_slices: number
  assigned_slices: number
  qualified_teacher_reviewers: number
  programs: SubjectSummary[]
  generated_at: string
}

const count = (value: number | undefined) => Number.isFinite(value) ? value!.toLocaleString() : '—'

export default function ProfessionalQuestionReviewPanel({ client }: { client: SupabaseClient }) {
  const [summary, setSummary] = useState<ReviewSummary | null>(null)
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const [filter, setFilter] = useState('')

  async function load() {
    if (busy) return
    setBusy(true); setError('')
    try {
      const {data, error} = await client.rpc('get_admin_question_review_progress_v39')
      if (error) throw error
      if (!data || typeof data !== 'object' || !Number.isFinite(data.active_questions) ||
        !Array.isArray(data.programs)) throw new Error('The backend did not provide a valid review progress report.')
      setSummary(data as ReviewSummary)
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Could not read professional question review progress.')
      setSummary(null)
    } finally {
      setBusy(false)
    }
  }

  const visible = (summary?.programs ?? []).filter(s =>
    `${s.subject_title} ${s.program_key} Grade ${s.grade_level ?? ''}`.toLocaleLowerCase().includes(filter.toLocaleLowerCase()))

  return <section className="panel" aria-label="Professional question review oversight">
    <div className="module-head">
      <div><h2>Professional question-review progress</h2>
        <p>Track verified subject-teacher decisions across the active question bank. Administration can inspect counts and verify teachers, but cannot approve questions on their behalf.</p>
      </div>
      <button type="button" className="refresh" onClick={() => void load()} disabled={busy}>{busy ? 'Loading…' : summary ? 'Refresh teacher review counts' : 'Load teacher review counts'}</button>
    </div>
    <p className="muted">These numbers come from the MELA backend when the professional review database upgrade is installed. Unreviewed or machine-validated questions do not count as professionally approved.</p>
    {error && <div className="error" role="alert">{error} Verify that the professional review migration has been installed in the actual MELA database and your MFA-protected admin account is authorized.</div>}
    {summary && <>
      <div className="stats-row">
        <div><strong>{count(summary.active_questions)}</strong><span>Active questions</span></div>
        <div><strong>{count(summary.teacher_approved)}</strong><span>Recorded teacher-approved</span></div>
        <div><strong>{count(summary.teacher_changes_required)}</strong><span>Changes required</span></div>
        <div><strong>{count(summary.pending_or_unverified)}</strong><span>Pending or unverified</span></div>
      </div>
      <p>Review slices: {count(summary.review_slices)} · Claimed: {count(summary.assigned_slices)} · Active authorized teacher reviewers: {count(summary.qualified_teacher_reviewers)}</p>
      <p className="muted">Latest backend report: {summary.generated_at ? new Date(summary.generated_at).toLocaleString() : 'date unavailable'}.</p>
      <div className="toolbar"><label>Find subject or grade
        <input aria-label="Filter question review subjects" value={filter} onChange={event => setFilter(event.target.value)} placeholder="Mathematics, Grade 8" />
      </label></div>
      <div className="table-wrap"><table><thead><tr>
        <th>Grade</th><th>Subject</th><th>Active</th><th>Teacher approved</th><th>Corrections</th><th>Pending / unknown</th>
      </tr></thead><tbody>
        {visible.map(p => <tr key={p.program_key}>
          <td>{p.grade_level ?? 'Higher ed'}</td><td><strong>{p.subject_title}</strong><small>{p.program_key}</small></td>
          <td>{count(p.total)}</td><td>{count(p.teacher_approved)}</td><td>{count(p.needs_changes)}</td><td>{count(p.remaining)}</td>
        </tr>)}
        {!visible.length && <tr><td colSpan={6} className="empty">No subjects match this filter.</td></tr>}
      </tbody></table></div>
      <p className="muted">This is an audit summary, not an independently certified grade/subject curriculum assessment. Check source references, human review qualifications and the staging QA protocol before launch.</p>
    </>}
  </section>
}
