import { useEffect, useMemo, useState } from 'react'
import type { SupabaseClient } from '@supabase/supabase-js'

type Certification = {
  assessment_id: string; assessment_title: string; category?: string; language_code: string; status: string
  reviewer_notes?: string | null; certified_at?: string | null; translation_count: number; source_count: number; approved_reviews: number
}
type Qualification = { reviewer_id: string; full_name?: string; email?: string; language_code: string; qualified: boolean; qualification_notes?: string | null; approved_at?: string | null }
type Assignment = { id: string; assessment_id: string; assessment_title: string; language_code: string; reviewer_id: string; reviewer_name?: string; reviewer_email?: string; status: string; reviewer_notes?: string | null; assigned_at?: string; submitted_at?: string | null }
type Candidate = { id: string; full_name?: string; email?: string; role?: string }
type StatusPayload = { certifications?: Certification[]; qualifications?: Qualification[]; assignments?: Assignment[]; candidate_reviewers?: Candidate[] }

const languages: Record<string,string> = { am: 'Amharic', om: 'Afaan Oromo', ti: 'Tigrinya', so: 'Somali' }

export default function AssessmentLanguageReviewPanel({ client }: { client: SupabaseClient }) {
  const [data, setData] = useState<StatusPayload>({})
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')
  const [revision, setRevision] = useState(0)
  const [reviewerId, setReviewerId] = useState('')
  const [language, setLanguage] = useState('am')
  const [qualificationNote, setQualificationNote] = useState('')
  const [assignReviewerId, setAssignReviewerId] = useState('')
  const [assignKey, setAssignKey] = useState('')
  const [certifyKey, setCertifyKey] = useState('')
  const [certifyNote, setCertifyNote] = useState('')

  useEffect(() => {
    let active = true
    const load = async () => {
      setBusy(true); setError('')
      try {
        const { data: result, error } = await client.rpc('admin_get_assessment_language_review_status')
        if (error) throw error
        if (active) setData((result ?? {}) as StatusPayload)
      } catch (cause) { if (active) setError(cause instanceof Error ? cause.message : 'Language review status could not be loaded.') }
      finally { if (active) setBusy(false) }
    }
    void load()
    return () => { active = false }
  }, [client, revision])

  const certifications = Array.isArray(data.certifications) ? data.certifications : []
  const qualifications = Array.isArray(data.qualifications) ? data.qualifications : []
  const assignments = Array.isArray(data.assignments) ? data.assignments : []
  const candidates = Array.isArray(data.candidate_reviewers) ? data.candidate_reviewers : []
  const qualifiedForAssign = useMemo(() => {
    if (!assignKey) return [] as Qualification[]
    const code = assignKey.split('|')[1]
    return qualifications.filter(row => row.qualified && row.language_code === code)
  }, [assignKey, qualifications])

  const mutate = async (fn: () => Promise<void>, message: string) => {
    if (busy) return
    setBusy(true); setError(''); setSuccess('')
    try { await fn(); setSuccess(message); setRevision(value => value + 1) }
    catch (cause) { setError(cause instanceof Error ? cause.message : 'Language review operation failed.') }
    finally { setBusy(false) }
  }

  const qualify = (qualified: boolean) => void mutate(async () => {
    if (!reviewerId || qualificationNote.trim().length < 5) throw new Error('Choose a reviewer and record qualification evidence.')
    const { error } = await client.rpc('admin_qualify_assessment_language_reviewer', {
      p_reviewer_id: reviewerId, p_language_code: language, p_qualified: qualified, p_notes: qualificationNote.trim(),
    })
    if (error) throw error
    setQualificationNote('')
  }, qualified ? 'Language reviewer qualification saved.' : 'Language reviewer qualification revoked.')

  const assign = () => void mutate(async () => {
    if (!assignKey || !assignReviewerId) throw new Error('Choose an assessment language and a qualified reviewer.')
    const [assessmentId, languageCode] = assignKey.split('|')
    const { error } = await client.rpc('admin_assign_assessment_language_reviewer', {
      p_assessment_id: assessmentId, p_language_code: languageCode, p_reviewer_id: assignReviewerId,
    })
    if (error) throw error
    setAssignReviewerId('')
  }, 'Reviewer assignment saved.')

  const certify = () => void mutate(async () => {
    if (!certifyKey) throw new Error('Choose a certification.')
    const [assessmentId, languageCode] = certifyKey.split('|')
    const { error } = await client.rpc('admin_certify_assessment_language', {
      p_assessment_id: assessmentId, p_language_code: languageCode, p_notes: certifyNote.trim() || null,
    })
    if (error) throw error
    setCertifyNote('')
  }, 'Assessment language certified after server verification of two independent approvals and a complete current translation bundle.')

  const complete = certifications.filter(row => row.translation_count === row.source_count && row.source_count > 0).length
  const certified = certifications.filter(row => row.status === 'certified').length
  const twoApprovals = certifications.filter(row => row.approved_reviews >= 2).length

  return <section className="panel" aria-label="Assessment language certification">
    <div className="module-head"><div><h2>Assessment language certification</h2><p>Coordinate bilingual reviewers for Amharic, Afaan Oromo, Tigrinya and Somali. Certification stays blocked until the bundle is complete and two independent qualified reviewers approve it.</p></div><button className="refresh" onClick={() => setRevision(v => v + 1)} disabled={busy}>Refresh</button></div>
    <section className="grid"><div className="metric"><span>Certification targets</span><strong>{certifications.length}</strong><small>Assessment-language pairs</small></div><div className="metric"><span>Complete translation bundles</span><strong>{complete}</strong><small>{certifications.length - complete} still incomplete</small></div><div className="metric"><span>Two reviewer approvals</span><strong>{twoApprovals}</strong><small>Required before certification</small></div><div className="metric"><span>Certified</span><strong>{certified}</strong><small>Human certified</small></div></section>
    {error && <div className="error" role="alert">{error}</div>}{success && <p role="status">{success}</p>}

    <div className="detail-card"><h3>1. Qualify a bilingual reviewer</h3><p className="muted">Record evidence of language competence before assigning credential assessment review.</p><div className="toolbar">
      <select aria-label="Reviewer" value={reviewerId} onChange={e => setReviewerId(e.target.value)} disabled={busy}><option value="">Choose reviewer</option>{candidates.map(c => <option key={c.id} value={c.id}>{c.full_name || c.email || c.id} · {c.role || 'user'}</option>)}</select>
      <select aria-label="Language" value={language} onChange={e => setLanguage(e.target.value)} disabled={busy}>{Object.entries(languages).map(([code,label]) => <option key={code} value={code}>{label}</option>)}</select>
    </div><label>Qualification evidence<textarea value={qualificationNote} onChange={e => setQualificationNote(e.target.value)} maxLength={2000} disabled={busy} placeholder="Example: native/professional fluency, teaching or translation background, evidence checked." /></label><div className="toolbar"><button disabled={busy || !reviewerId || qualificationNote.trim().length < 5} onClick={() => qualify(true)}>Qualify reviewer</button><button className="danger-btn" disabled={busy || !reviewerId || qualificationNote.trim().length < 5} onClick={() => qualify(false)}>Revoke qualification</button></div></div>

    <div className="detail-card"><h3>2. Assign a qualified reviewer</h3><div className="toolbar"><select aria-label="Assessment language" value={assignKey} onChange={e => { setAssignKey(e.target.value); setAssignReviewerId('') }} disabled={busy}><option value="">Choose assessment language</option>{certifications.filter(c => c.status !== 'certified').map(c => <option key={`${c.assessment_id}|${c.language_code}`} value={`${c.assessment_id}|${c.language_code}`}>{c.assessment_title} · {languages[c.language_code] || c.language_code} · {c.translation_count}/{c.source_count} translated</option>)}</select><select aria-label="Qualified reviewer" value={assignReviewerId} onChange={e => setAssignReviewerId(e.target.value)} disabled={busy || !assignKey}><option value="">Choose qualified reviewer</option>{qualifiedForAssign.map(q => <option key={`${q.reviewer_id}-${q.language_code}`} value={q.reviewer_id}>{q.full_name || q.email || q.reviewer_id}</option>)}</select><button onClick={assign} disabled={busy || !assignKey || !assignReviewerId}>Assign reviewer</button></div></div>

    <div className="detail-card"><h3>3. Certify after two approvals</h3><div className="toolbar"><select aria-label="Certification ready target" value={certifyKey} onChange={e => setCertifyKey(e.target.value)} disabled={busy}><option value="">Choose target</option>{certifications.map(c => <option key={`${c.assessment_id}|${c.language_code}`} value={`${c.assessment_id}|${c.language_code}`}>{c.assessment_title} · {languages[c.language_code] || c.language_code} · translations {c.translation_count}/{c.source_count} · approvals {c.approved_reviews}/2 · {c.status}</option>)}</select></div><label>Certification note<textarea value={certifyNote} onChange={e => setCertifyNote(e.target.value)} maxLength={2000} disabled={busy} placeholder="Optional final certification note." /></label><button onClick={certify} disabled={busy || !certifyKey}>Run certification checks</button></div>

    <h3>Certification matrix</h3><div className="table-wrap"><table><thead><tr><th>Assessment</th><th>Language</th><th>Translations</th><th>Approvals</th><th>Status</th></tr></thead><tbody>{certifications.map(c => <tr key={`${c.assessment_id}-${c.language_code}`}><td><strong>{c.assessment_title}</strong><small>{c.category || 'Assessment'}</small></td><td>{languages[c.language_code] || c.language_code}</td><td>{c.translation_count}/{c.source_count}</td><td>{c.approved_reviews}/2</td><td><span className={`status-pill ${c.status}`}>{c.status}</span></td></tr>)}{!certifications.length && !busy && <tr><td colSpan={5} className="empty">No certification targets found.</td></tr>}</tbody></table></div>

    <h3>Reviewer qualifications</h3><div className="table-wrap"><table><thead><tr><th>Reviewer</th><th>Language</th><th>Qualified</th><th>Evidence</th></tr></thead><tbody>{qualifications.map(q => <tr key={`${q.reviewer_id}-${q.language_code}`}><td>{q.full_name || q.email || q.reviewer_id}</td><td>{languages[q.language_code] || q.language_code}</td><td>{q.qualified ? 'Yes' : 'No'}</td><td>{q.qualification_notes || '—'}</td></tr>)}{!qualifications.length && <tr><td colSpan={4} className="empty">No bilingual reviewers have been qualified yet.</td></tr>}</tbody></table></div>

    <h3>Assignments</h3><div className="table-wrap"><table><thead><tr><th>Assessment</th><th>Language</th><th>Reviewer</th><th>Status</th><th>Notes</th></tr></thead><tbody>{assignments.map(a => <tr key={a.id}><td>{a.assessment_title}</td><td>{languages[a.language_code] || a.language_code}</td><td>{a.reviewer_name || a.reviewer_email || a.reviewer_id}</td><td>{a.status}</td><td>{a.reviewer_notes || '—'}</td></tr>)}{!assignments.length && <tr><td colSpan={5} className="empty">No language review assignments yet.</td></tr>}</tbody></table></div>
  </section>
}
