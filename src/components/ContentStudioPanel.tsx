import { useEffect, useMemo, useState } from 'react'
import type { SupabaseClient } from '@supabase/supabase-js'
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
  const [revision, setRevision] = useState(0)

  useEffect(() => {
    let active = true
    setBusy(true)
    setError('')
    Promise.all([
      contentAdminApi(client, 'overview'),
      contentAdminApi(client, 'drafts.list', { limit: 100 }),
    ]).then(([overviewResult, draftResult]) => {
      if (!active) return
      setOverview(overviewResult as Overview)
      setDrafts(Array.isArray(draftResult?.data) ? draftResult.data : [])
    }).catch((cause) => {
      if (active) setError(cause instanceof Error ? cause.message : 'Could not load the Content Studio.')
    }).finally(() => { if (active) setBusy(false) })
    return () => { active = false }
  }, [client, revision])

  const pendingTranslations = useMemo(() => (
    overview?.translations.reduce((total, row) => total + (row.review_status === 'pending' ? Number(row.item_count) : 0), 0) ?? 0
  ), [overview])

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
      <label>Structured payload<textarea value={form.payloadText} onChange={event => setForm(current => ({ ...current, payloadText: event.target.value }))} rows={12} spellCheck={false} required disabled={busy}/></label>
      <div className="toolbar"><button type="submit" disabled={busy || !form.title.trim()}>{busy ? 'Saving…' : 'Save draft'}</button>{form.id && <span className="muted">Editing version {form.expectedVersion ?? '—'}; the server creates the next immutable snapshot.</span>}</div>
    </form>

    {overview && <section>
      <div className="module-head"><div><h3>Empty program queue</h3><p>Programs with neither chapters nor questions. Create a reviewable seed draft without publishing unverified educational claims.</p></div><strong>{overview.empty_programs.length}</strong></div>
      <div className="table-wrap"><table><thead><tr><th>Program</th><th>Stage</th><th>Inventory</th><th/></tr></thead><tbody>
        {overview.empty_programs.map(program => <tr key={program.program_key}><td><strong>{program.title}</strong><small>{program.program_key}</small></td><td>{program.stage_key}{program.grade_level ? ` · Grade ${program.grade_level}` : ''}</td><td>{program.chapter_count} chapters · {program.question_count} questions</td><td><button onClick={() => seedGap(program)} disabled={busy}>Prepare seed</button></td></tr>)}
        {!overview.empty_programs.length && <tr><td colSpan={4}>No empty active programs.</td></tr>}
      </tbody></table></div>
    </section>}

    {overview && <section>
      <h3>Translation review inventory</h3>
      <div className="table-wrap"><table><thead><tr><th>Source</th><th>Language</th><th>Status</th><th>Items</th></tr></thead><tbody>
        {overview.translations.map(row => <tr key={`${row.source}-${row.language_code}-${row.review_status}`}><td>{row.source.replaceAll('_', ' ')}</td><td>{langName(row.language_code)}</td><td>{row.review_status}</td><td>{num(row.item_count)}</td></tr>)}
      </tbody></table></div>
    </section>}

    {overview && <section>
      <h3>Qualified-review queues</h3>
      <p className="muted">Read-only here. Educator/language reviewer authorization remains enforced by the dedicated review workflow.</p>
      <div className="grid"><div className="metric"><span>Chapter queue shown</span><strong>{overview.chapter_reviews.length}</strong><small>Up to 50 oldest/highest-priority items</small></div><div className="metric"><span>Question batches shown</span><strong>{overview.question_review_batches.length}</strong><small>Up to 50 review batches</small></div></div>
    </section>}

    <section>
      <div className="module-head"><div><h3>Versioned drafts</h3><p>Submitted drafts remain non-public until the qualified review and publishing workflow is completed.</p></div><strong>{drafts.length}</strong></div>
      <div className="table-wrap"><table><thead><tr><th>Draft</th><th>Status</th><th>Version</th><th>Updated</th><th>Actions</th></tr></thead><tbody>
        {drafts.map(draft => <tr key={draft.id}><td><strong>{draft.title}</strong><small>{draft.entity_type} · {draft.program_key ?? 'no program'} · {langName(draft.language_code)}</small></td><td><span className={`status-pill ${draft.status}`}>{draft.status}</span></td><td>v{draft.version}</td><td>{dateText(draft.updated_at)}</td><td><div className="toolbar">{['draft','rejected'].includes(draft.status) && <button onClick={() => editDraft(draft)} disabled={busy}>Edit</button>}{['draft','rejected'].includes(draft.status) && <button onClick={() => void submitDraft(draft)} disabled={busy}>Submit</button>}<button onClick={() => void loadVersions(draft)} disabled={busy}>Versions</button>{draft.status !== 'archived' && <button className="secondary" onClick={() => void archiveDraft(draft)} disabled={busy}>Archive</button>}</div></td></tr>)}
        {!drafts.length && <tr><td colSpan={5}>No content drafts yet.</td></tr>}
      </tbody></table></div>
    </section>

    {!!versions.length && <section className="panel"><h3>Version history</h3><div className="table-wrap"><table><thead><tr><th>Version</th><th>Change</th><th>Created</th><th>Snapshot</th></tr></thead><tbody>{versions.map((version: any) => <tr key={String(version.id)}><td>v{String(version.version_no)}</td><td>{String(version.change_kind)}</td><td>{version.created_at ? dateText(String(version.created_at)) : '—'}</td><td><details><summary>Inspect</summary><pre style={{ whiteSpace: 'pre-wrap', maxWidth: '60rem' }}>{JSON.stringify(version.snapshot, null, 2)}</pre></details></td></tr>)}</tbody></table></div></section>}
  </section>
}
