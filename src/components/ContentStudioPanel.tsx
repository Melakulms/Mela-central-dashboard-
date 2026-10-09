import { useEffect, useMemo, useState } from 'react'
import type { SupabaseClient } from '@supabase/supabase-js'
import ContentBacklog from './ContentBacklog'
import { contentAdminApi } from '../lib/admin-api'

type Summary = {
  active_programs: number
  chapters: number
  source_verified_chapters: number
  active_questions: number
  educator_verified_questions: number
  empty_programs: number
  approved_chapter_reviews: number
  pending_chapter_reviews: number
  draft_count: number
  submitted_drafts: number
}

type ProgramInventory = {
  program_key: string
  stage_key: string
  grade_level: number | null
  subject_title: string | null
  title: string
  chapter_count: number
  question_count: number
  source_verified_chapters: number
  educator_verified_questions: number
  has_content: boolean
}

type TranslationInventory = {
  source: string
  language_code: string
  review_status: string
  item_count: number
}

type ContentDraft = {
  id: string
  entity_type: string
  target_id: string | null
  program_key: string | null
  language_code: string
  title: string
  payload: Record<string, unknown>
  status: string
  version: number
  updated_at: string
}

type Overview = {
  summary: Summary
  empty_programs: ProgramInventory[]
  translations: TranslationInventory[]
  chapter_reviews: Record<string, unknown>[]
  question_review_batches: Record<string, unknown>[]
}

type DraftForm = {
  id: string
  expectedVersion: number | null
  entityType: string
  targetId: string
  programKey: string
  languageCode: string
  title: string
  payloadText: string
}

const EMPTY_FORM: DraftForm = {
  id: '',
  expectedVersion: null,
  entityType: 'program_seed',
  targetId: '',
  programKey: '',
  languageCode: 'en',
  title: '',
  payloadText: '{\n  "summary": "",\n  "objectives": [],\n  "content": ""\n}',
}

const langName = (code: string) => ({ en: 'English', am: 'Amharic', om: 'Afaan Oromo', ti: 'Tigrinya', so: 'Somali' }[code] ?? code)
const num = (value: unknown) => Number(value ?? 0).toLocaleString()
const dateText = (value: string) => new Date(value).toLocaleString()

export default function ContentStudioPanel({ client }: { client: SupabaseClient }) {
  const [overview, setOverview] = useState<Overview | null>(null)
  const [drafts, setDrafts] = useState<ContentDraft[]>([])
  const [form, setForm] = useState<DraftForm>(EMPTY_FORM)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')
  const [versions, setVersions] = useState<Record<string, unknown>[]>([])
  const [draftOffset, setDraftOffset] = useState(0)
  const [draftTotal, setDraftTotal] = useState(0)
  const [draftStatus, setDraftStatus] = useState('')
  const [draftBusy, setDraftBusy] = useState(false)
  const [draftError, setDraftError] = useState('')
  const [revision, setRevision] = useState(0)

  useEffect(() => {
    let active = true
    setBusy(true)
    setError('')
    Promise.all([
      contentAdminApi(client, 'overview'),

    ]).then(([overviewResult]) => {
      if (!active) return
      setOverview(overviewResult as Overview)
    }).catch((cause) => {
      if (active) setError(cause instanceof Error ? cause.message : 'Could not load the Content Studio.')
    }).finally(() => { if (active) setBusy(false) })
    return () => { active = false }
  }, [client, revision])

  useEffect(() => {
    let active = true
    setDraftBusy(true); setDraftError(''); setDrafts([])
    contentAdminApi(client, 'drafts.list', { limit: 25, offset: draftOffset, status: draftStatus || undefined }).then(result => {
      if (!active) return
      const total = Number(result.total ?? 0)
      if (draftOffset > 0 && draftOffset >= total) { setDraftOffset(Math.max(0, Math.floor((total - 1) / 25) * 25)); return }
      setDrafts(result.data ?? []); setDraftTotal(total)
    }).catch(cause => { if (active) setDraftError(cause instanceof Error ? cause.message : 'Could not load drafts.') })
      .finally(() => { if (active) setDraftBusy(false) })
    return () => { active = false }
  }, [client, draftOffset, draftStatus, revision])

  const pendingTranslations = useMemo(() => (
    overview?.translations.reduce((total, row) => total + (row.review_status === 'pending' ? Number(row.item_count) : 0), 0) ?? 0
  ), [overview])

  const coursePayload = useMemo(() => {
    try {
      const value = JSON.parse(form.payloadText)
      return form.entityType === 'material' && typeof value?.course_id === 'string' ? value as Record<string, unknown> : null
    } catch { return null }
  }, [form.payloadText, form.entityType])
  const updateCourseField = (key: string, value: unknown) => {
    setForm(current => {
      const payload = JSON.parse(current.payloadText)
      return { ...current, payloadText: JSON.stringify({ ...payload, [key]: value }, null, 2) }
    })
  }

  const resetForm = () => {
    setForm(EMPTY_FORM)
    setVersions([])
    setError('')
    setSuccess('')
  }

  const seedGap = (program: ProgramInventory) => {
    setForm({
      ...EMPTY_FORM,
      entityType: 'program_seed',
      programKey: program.program_key,
      title: `${program.title} launch content seed`,
      payloadText: JSON.stringify({
        program_key: program.program_key,
        stage_key: program.stage_key,
        grade_level: program.grade_level,
        subject_title: program.subject_title,
        status: 'needs_qualified_review',
        objectives: [],
        content: '',
        assessment_notes: '',
        translation_notes: '',
      }, null, 2),
    })
    window.scrollTo({ top: 0, behavior: 'smooth' })
  }

  const prepareCourse = (course: Record<string, unknown>) => {
    setForm({ ...EMPTY_FORM, entityType: 'material', targetId: String(course.id), title: `${course.title}: new lesson`, payloadText: JSON.stringify({
      course_id: course.id, course_slug: course.slug, course_title: course.title,
      module_title: '', module_position: 1, lesson_position: 1,
      title: '', duration_minutes: 15, objectives: [], content_text: '',
      practice: '', answer_explanations: '', sources: [], language_code: 'en',
      editorial_status: 'needs_qualified_review',
    }, null, 2) })
    setVersions([]); setError(''); setSuccess('')
    window.scrollTo({ top: 0, behavior: 'smooth' })
  }

  const editDraft = (draft: ContentDraft) => {
    setForm({
      id: draft.id,
      expectedVersion: draft.version,
      entityType: draft.entity_type,
      targetId: draft.target_id ?? '',
      programKey: draft.program_key ?? '',
      languageCode: draft.language_code,
      title: draft.title,
      payloadText: JSON.stringify(draft.payload ?? {}, null, 2),
    })
    setVersions([])
    setError('')
    setSuccess('')
    window.scrollTo({ top: 0, behavior: 'smooth' })
  }

  const saveDraft = async (event: React.FormEvent) => {
    event.preventDefault()
    setBusy(true)
    setError('')
    setSuccess('')
    try {
      const payload = JSON.parse(form.payloadText)
      if (!payload || typeof payload !== 'object' || Array.isArray(payload)) throw new Error('Draft payload must be a JSON object.')
      const result = await contentAdminApi(client, 'draft.save', {
        draft_id: form.id || undefined,
        expected_version: form.expectedVersion ?? undefined,
        entity_type: form.entityType,
        target_id: form.targetId || undefined,
        program_key: form.programKey || undefined,
        language_code: form.languageCode,
        title: form.title,
        payload,
      })
      const saved = result.data as ContentDraft
      setSuccess(`Draft saved as version ${saved.version}.`)
      setForm(current => ({ ...current, id: saved.id, expectedVersion: saved.version }))
      setRevision(value => value + 1)
    } catch (cause) {
      setError(cause instanceof SyntaxError ? 'Draft payload is not valid JSON.' : cause instanceof Error ? cause.message : 'Could not save the draft.')
    } finally { setBusy(false) }
  }

  const submitDraft = async (draft: ContentDraft) => {
    setBusy(true)
    setError('')
    setSuccess('')
    try {
      const result = await contentAdminApi(client, 'draft.submit', { draft_id: draft.id })
      setSuccess(result.message ?? 'Draft submitted for qualified review.')
      if (form.id === draft.id) setForm(EMPTY_FORM)
      setRevision(value => value + 1)
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Could not submit the draft.')
    } finally { setBusy(false) }
  }

  const archiveDraft = async (draft: ContentDraft) => {
    setBusy(true)
    setError('')
    setSuccess('')
    try {
      await contentAdminApi(client, 'draft.archive', { draft_id: draft.id })
      setSuccess('Draft archived; version history is retained.')
      if (form.id === draft.id) setForm(EMPTY_FORM)
      setRevision(value => value + 1)
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Could not archive the draft.')
    } finally { setBusy(false) }
  }

  const loadVersions = async (draft: ContentDraft) => {
    setBusy(true)
    setError('')
    try {
      const result = await contentAdminApi(client, 'draft.versions', { draft_id: draft.id })
      setVersions(Array.isArray(result.data) ? result.data : [])
      setForm(current => ({ ...current, id: draft.id, expectedVersion: draft.version }))
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Could not load version history.')
    } finally { setBusy(false) }
  }

  return <section className="panel" aria-labelledby="content-studio-heading">
    <div className="module-head">
      <div>
        <h2 id="content-studio-heading">Content Studio</h2>
        <p>Create versioned drafts, inspect empty programs and review queues, and prepare translations. Publication is intentionally locked until qualified review evidence exists.</p>
      </div>
      <button className="refresh" onClick={() => setRevision(value => value + 1)} disabled={busy}>{busy ? 'Refreshing…' : 'Refresh content'}</button>
    </div>

    {error && <div className="error" role="alert">{error}</div>}
    {success && <p role="status">{success}</p>}

    {overview && <>
      <section className="grid" aria-label="Content quality summary">
        <div className="metric"><span>Programs</span><strong>{num(overview.summary.active_programs)}</strong><small>{num(overview.summary.empty_programs)} empty</small></div>
        <div className="metric"><span>Chapters</span><strong>{num(overview.summary.chapters)}</strong><small>{num(overview.summary.source_verified_chapters)} source verified</small></div>
        <div className="metric"><span>Questions</span><strong>{num(overview.summary.active_questions)}</strong><small>{num(overview.summary.educator_verified_questions)} educator verified</small></div>
        <div className="metric"><span>Translations pending</span><strong>{num(pendingTranslations)}</strong><small>Amharic · Afaan Oromo · Tigrinya · Somali</small></div>
      </section>

      <div className="notice" role="note">
        Qualified review remains external to this admin editing surface. Current chapter approvals: <strong>{num(overview.summary.approved_chapter_reviews)}</strong>; pending: <strong>{num(overview.summary.pending_chapter_reviews)}</strong>. Admin draft submission cannot convert either count into a pass.
      </div>
    </>}

    <form className="panel" onSubmit={saveDraft} aria-label="Content draft editor">
      <div className="module-head"><div><h3>{form.id ? 'Edit versioned draft' : 'Create versioned draft'}</h3><p>Drafts do not become learner-visible content when saved or submitted.</p></div>{form.id && <button type="button" className="secondary" onClick={resetForm} disabled={busy}>New draft</button>}</div>
      <div className="toolbar">
        <label>Type<select value={form.entityType} onChange={event => setForm(current => ({ ...current, entityType: event.target.value }))} disabled={busy}>
          <option value="program_seed">Program seed</option><option value="chapter">Chapter</option><option value="material">Lesson/material</option><option value="question">Question</option><option value="translation">Translation</option><option value="book">Book</option>
        </select></label>
        <label>Language<select value={form.languageCode} onChange={event => setForm(current => ({ ...current, languageCode: event.target.value }))} disabled={busy}>
          <option value="en">English</option><option value="am">Amharic</option><option value="om">Afaan Oromo</option><option value="ti">Tigrinya</option><option value="so">Somali</option>
        </select></label>
        <label>Program key<input value={form.programKey} onChange={event => setForm(current => ({ ...current, programKey: event.target.value }))} maxLength={160} disabled={busy}/></label>
        <label>Existing target ID<input value={form.targetId} onChange={event => setForm(current => ({ ...current, targetId: event.target.value }))} placeholder="Optional UUID" disabled={busy}/></label>
      </div>
      <label>Draft title<input value={form.title} onChange={event => setForm(current => ({ ...current, title: event.target.value }))} maxLength={300} required disabled={busy}/></label>
      {coursePayload ? <fieldset disabled={busy}><legend>Course lesson draft</legend><p>{String(coursePayload.course_title ?? coursePayload.course_slug ?? coursePayload.course_id)}</p>
        <label>Lesson title<input value={String(coursePayload.title ?? '')} onChange={event=>updateCourseField('title',event.target.value)} maxLength={300}/></label>
        <label>Module title<input value={String(coursePayload.module_title ?? '')} onChange={event=>updateCourseField('module_title',event.target.value)} maxLength={200}/></label>
        <div className="toolbar">{[['module_position','Module number'],['lesson_position','Lesson number'],['duration_minutes','Minutes']].map(([key,label])=><label key={key}>{label}<input type="number" min={1} step={1} value={Number(coursePayload[key] ?? 1)} onChange={event=>updateCourseField(key,Number(event.target.value))}/></label>)}</div>
        <label>Learning objectives (one per line)<textarea rows={4} value={Array.isArray(coursePayload.objectives) ? coursePayload.objectives.join('\n') : ''} onChange={event=>updateCourseField('objectives',event.target.value.split('\n'))}/></label>
        <label>Lesson content<textarea rows={14} value={String(coursePayload.content_text ?? '')} onChange={event=>updateCourseField('content_text',event.target.value)}/></label>
        <label>Practice exercise<textarea rows={5} value={String(coursePayload.practice ?? '')} onChange={event=>updateCourseField('practice',event.target.value)}/></label>
        <label>Answer explanations<textarea rows={5} value={String(coursePayload.answer_explanations ?? '')} onChange={event=>updateCourseField('answer_explanations',event.target.value)}/></label>
        <label>Sources and permissions notes (one per line)<textarea rows={4} value={Array.isArray(coursePayload.sources) ? coursePayload.sources.join('\n') : ''} onChange={event=>updateCourseField('sources',event.target.value.split('\n'))}/></label>
        <p className="muted">Saving retains a private draft. Submission requires lesson text, an objective, ordering, and a duration; qualified review is still required before publication.</p>
      </fieldset> : <label>Structured payload<textarea value={form.payloadText} onChange={event => setForm(current => ({ ...current, payloadText: event.target.value }))} rows={12} spellCheck={false} required disabled={busy}/></label>}
      <div className="toolbar"><button type="submit" disabled={busy || !form.title.trim()}>{busy ? 'Saving…' : 'Save draft'}</button>{form.id && <span className="muted">Editing version {form.expectedVersion ?? '—'}; the server creates the next immutable snapshot.</span>}</div>
    </form>

    <ContentBacklog client={client} onPrepareCourse={prepareCourse} onPrepareProgram={row => seedGap(row as ProgramInventory)} />

    {overview && <section>
      <h3>Translation review inventory</h3>
      <div className="table-wrap"><table><thead><tr><th>Source</th><th>Language</th><th>Status</th><th>Items</th></tr></thead><tbody>
        {overview.translations.map(row => <tr key={`${row.source}-${row.language_code}-${row.review_status}`}><td>{row.source.replaceAll('_', ' ')}</td><td>{langName(row.language_code)}</td><td>{row.review_status}</td><td>{num(row.item_count)}</td></tr>)}
      </tbody></table></div>
    </section>}

    <section>
      <div className="module-head"><div><h3>Versioned drafts</h3><p>Submitted drafts remain non-public until the qualified review and publishing workflow is completed.</p></div><strong>{draftTotal}</strong></div>
      <div className="toolbar"><label>Draft status<select value={draftStatus} onChange={event => {setDraftStatus(event.target.value);setDraftOffset(0)}}><option value="">All statuses</option>{['draft','submitted','approved','rejected','published','archived'].map(status => <option key={status} value={status}>{status}</option>)}</select></label><span>{draftBusy ? 'Loading drafts…' : `${drafts.length} shown of ${draftTotal}`}</span></div>
      {draftError && <div role="alert" className="error">{draftError}<button onClick={() => setRevision(v=>v+1)}>Retry drafts</button></div>}
      <div className="table-wrap"><table><thead><tr><th>Draft</th><th>Status</th><th>Version</th><th>Updated</th><th>Actions</th></tr></thead><tbody>
        {drafts.map(draft => <tr key={draft.id}><td><strong>{draft.title}</strong><small>{draft.entity_type} · {draft.program_key ?? 'no program'} · {langName(draft.language_code)}</small></td><td><span className={`status-pill ${draft.status}`}>{draft.status}</span></td><td>v{draft.version}</td><td>{dateText(draft.updated_at)}</td><td><div className="toolbar">{['draft','rejected'].includes(draft.status) && <button onClick={() => editDraft(draft)} disabled={busy}>Edit</button>}{['draft','rejected'].includes(draft.status) && <button onClick={() => void submitDraft(draft)} disabled={busy}>Submit</button>}<button onClick={() => void loadVersions(draft)} disabled={busy}>Versions</button>{draft.status !== 'archived' && <button className="secondary" onClick={() => void archiveDraft(draft)} disabled={busy}>Archive</button>}</div></td></tr>)}
        {!draftBusy && !draftError && !drafts.length && <tr><td colSpan={5}>No content drafts yet.</td></tr>}
      </tbody></table></div>
    </section>

      <div className="toolbar"><button disabled={draftBusy || draftOffset === 0} onClick={() => setDraftOffset(v=>Math.max(0,v-25))}>Previous drafts page</button><button disabled={draftBusy || draftOffset + 25 >= draftTotal} onClick={() => setDraftOffset(v=>v+25)}>Next drafts page</button></div>
    {!!versions.length && <section className="panel"><h3>Version history</h3><div className="table-wrap"><table><thead><tr><th>Version</th><th>Change</th><th>Created</th><th>Snapshot</th></tr></thead><tbody>{versions.map((version: any) => <tr key={String(version.id)}><td>v{String(version.version_no)}</td><td>{String(version.change_kind)}</td><td>{version.created_at ? dateText(String(version.created_at)) : '—'}</td><td><details><summary>Inspect</summary><pre style={{ whiteSpace: 'pre-wrap', maxWidth: '60rem' }}>{JSON.stringify(version.snapshot, null, 2)}</pre></details></td></tr>)}</tbody></table></div></section>}
  </section>
}
