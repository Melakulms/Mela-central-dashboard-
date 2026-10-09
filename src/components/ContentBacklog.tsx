import { useEffect, useState } from 'react'
import type { SupabaseClient } from '@supabase/supabase-js'
import { contentAdminApi } from '../lib/admin-api'

type Kind = 'courses' | 'programs' | 'chapters' | 'questions'
type Row = Record<string, unknown>
const PAGE_SIZE = 25
export default function ContentBacklog({ client, onPrepareCourse, onPrepareProgram }: {
  client: SupabaseClient
  onPrepareCourse: (course: Row) => void
  onPrepareProgram: (program: Row) => void
}) {
  const [kind, setKind] = useState<Kind>('courses')
  const [grade, setGrade] = useState('')
  const [program, setProgram] = useState('')
  const [search, setSearch] = useState('')
  const [missingOnly, setMissingOnly] = useState(false)
  const [offset, setOffset] = useState(0)
  const [total, setTotal] = useState(0)
  const [rows, setRows] = useState<Row[]>([])
  const [subjects, setSubjects] = useState<Row[]>([])
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [revision, setRevision] = useState(0)
  const [lessons, setLessons] = useState<Row[] | null>(null)
  const [lessonCourse, setLessonCourse] = useState('')
  const [lessonBusy, setLessonBusy] = useState(false)
  const [lessonError, setLessonError] = useState('')
  const [lessonOffset, setLessonOffset] = useState(0)
  const [lessonTotal, setLessonTotal] = useState(0)
  const [lessonId, setLessonId] = useState('')

  useEffect(() => {
    let active = true
    setBusy(true); setError(''); setRows([])
    const body = { limit: PAGE_SIZE, offset, grade_level: grade ? Number(grade) : undefined, program_key: program || undefined, search, missing_only: missingOnly, empty_only: missingOnly }
    const action = kind === 'courses' ? 'courses.list' : kind === 'programs' ? 'programs.list' : 'review.queue'
    contentAdminApi(client, action, { ...body, kind }).then(result => {
      if (!active) return
      const nextTotal = Number(result.total ?? 0)
      if (offset > 0 && offset >= nextTotal) { setOffset(Math.max(0, Math.floor((nextTotal - 1) / PAGE_SIZE) * PAGE_SIZE)); return }
      setRows(result.data ?? []); setTotal(nextTotal)
    }).catch(cause => { if (active) setError(cause instanceof Error ? cause.message : 'Could not load content inventory.') })
      .finally(() => { if (active) setBusy(false) })
    return () => { active = false }
  }, [client, kind, grade, program, search, missingOnly, offset, revision])

  useEffect(() => {
    let active = true
    setSubjects([])
    if (!grade || !['chapters', 'questions'].includes(kind)) return
    contentAdminApi(client, 'programs.list', { grade_level: Number(grade), limit: 200 }).then(result => {
      if (active) setSubjects(result.data ?? [])
    }).catch(cause => { if (active) setError(cause instanceof Error ? cause.message : 'Could not load subjects.') })
    return () => { active = false }
  }, [client, grade, kind, revision])

  useEffect(() => {
    let active = true
    setLessons(null); setLessonError('')
    if (!lessonId) return
    setLessonBusy(true)
    contentAdminApi(client, 'courses.lessons', { course_id: lessonId, limit: PAGE_SIZE, offset: lessonOffset }).then(result => {
      if (active) { setLessons(result.data ?? []); setLessonTotal(Number(result.total ?? 0)) }
    }).catch(cause => { if (active) setLessonError(cause instanceof Error ? cause.message : 'Could not load lessons.') })
      .finally(() => { if (active) setLessonBusy(false) })
    return () => { active = false }
  }, [client, lessonId, lessonOffset, revision])

  const resetPage = () => { setOffset(0); setLessonId(''); setLessons(null) }
  return <section className="panel" aria-labelledby="complete-content-backlog">
    <div className="module-head"><div><h3 id="complete-content-backlog">Complete content backlog</h3><p>Browse all records. Lesson availability is separate from qualified review and educational certification.</p></div><button className="refresh" disabled={busy} onClick={() => setRevision(v => v + 1)}>Reload inventory</button></div>
    <div className="toolbar">
      <label>Inventory<select value={kind} onChange={event => {setKind(event.target.value as Kind);setGrade('');setProgram('');setSearch('');setMissingOnly(false);resetPage()}}><option value="courses">Skill Academy courses</option><option value="programs">Curriculum programs</option><option value="chapters">Chapter review queue</option><option value="questions">Question review batches</option></select></label>
      {kind !== 'courses' && <label>Grade<select value={grade} onChange={event => {setGrade(event.target.value);setProgram('');resetPage()}}><option value="">All grades</option>{Array.from({length:12},(_,i)=>i+1).map(n=><option key={n} value={n}>Grade {n}</option>)}</select></label>}
      {['chapters','questions'].includes(kind) && <label>Subject<select value={program} disabled={!grade} onChange={event=>{setProgram(event.target.value);resetPage()}}><option value="">All subjects</option>{subjects.map(row=><option key={String(row.program_key)} value={String(row.program_key)}>{String(row.subject_title ?? row.title)} ({String(row.program_key)})</option>)}</select></label>}
      {['courses','programs'].includes(kind) && <><label>Search inventory<input type="search" value={search} onChange={event=>{setSearch(event.target.value);resetPage()}} maxLength={120}/></label><label><input type="checkbox" checked={missingOnly} onChange={event=>{setMissingOnly(event.target.checked);resetPage()}}/>Only content gaps</label></>}
    </div>
    {error && <div role="alert" className="error">{error}</div>}
    {busy ? <p role="status">Loading inventory…</p> : !error && <>
      <p role="status">{total ? `${offset + 1}–${Math.min(offset + rows.length,total)}` : '0'} of {total.toLocaleString()} records</p>
      <div className="table-wrap"><table><thead><tr><th>Content</th><th>Classification</th><th>Inventory / review</th><th>Actions</th></tr></thead><tbody>
        {rows.map(row=><tr key={String(row.id ?? row.program_key)}>
          <td><strong>{String(row.title ?? row.chapter_title ?? row.subject_title ?? row.program_key)}</strong><small>{String(row.slug ?? row.program_key ?? '')}</small></td>
          <td>{kind === 'courses' ? `${String(row.level ?? '')} · ${String(row.category ?? '')}` : `${row.grade_level ? `Grade ${row.grade_level}` : String(row.stage_key ?? '')} · ${String(row.subject_key ?? row.subject_title ?? '')}`}</td>
          <td>{kind === 'courses' ? <>{String(row.lesson_count)} lessons · {String(row.preview_lesson_count)} previews<small>{row.content_available ? 'Lesson text available' : 'Lessons in preparation'} · {row.is_published ? 'Listed' : 'Unpublished'}</small></> : kind === 'programs' ? `${row.chapter_count} chapters · ${row.question_count} questions` : kind === 'chapters' ? `${row.source_state} · ${row.status}` : `${row.generated_question_count} generated · ${row.deterministic_validated_count} deterministic · ${row.educator_verified_count} educator verified · ${row.review_status}`}</td>
          <td>{kind === 'courses' ? <><button onClick={()=>{setLessonCourse(String(row.title));setLessonId(String(row.id));setLessonOffset(0)}}>Inspect lessons</button><button className="secondary" onClick={()=>onPrepareCourse(row)}>Prepare lesson draft</button></> : kind === 'programs' ? <button onClick={()=>onPrepareProgram(row)}>Prepare program draft</button> : <span>Qualified educator review required</span>}</td>
        </tr>)}
        {!rows.length && <tr><td colSpan={4}>No records match these filters.</td></tr>}
      </tbody></table></div>
    </>}
    <div className="toolbar"><button disabled={busy || offset===0} onClick={()=>setOffset(v=>Math.max(0,v-PAGE_SIZE))}>Previous inventory page</button><button disabled={busy || offset+PAGE_SIZE>=total} onClick={()=>setOffset(v=>v+PAGE_SIZE)}>Next inventory page</button></div>
    {lessonId && <section className="panel"><div className="module-head"><h4>Lessons: {lessonCourse}</h4><button className="secondary" onClick={()=>{setLessonId('');setLessons(null)}}>Close lessons</button></div>
      {lessonBusy && <p role="status">Loading lesson text…</p>}{lessonError && <div role="alert" className="error">{lessonError}<button onClick={()=>setRevision(v=>v+1)}>Retry lessons</button></div>}
      {lessons && <><p>{lessonTotal} lessons; showing {lessons.length}</p>{lessons.map(lesson=><details key={String(lesson.id)}><summary>{String(lesson.module_title)} · {String(lesson.title)} · {String(lesson.duration_minutes)} min</summary><pre style={{whiteSpace:'pre-wrap',overflowWrap:'anywhere'}}>{String(lesson.content_text ?? '')}</pre></details>)}{!lessonTotal && <p>No lesson text has been authored for this course.</p>}<div className="toolbar"><button disabled={lessonBusy || lessonOffset===0} onClick={()=>setLessonOffset(v=>Math.max(0,v-PAGE_SIZE))}>Previous lesson page</button><button disabled={lessonBusy || lessonOffset+PAGE_SIZE>=lessonTotal} onClick={()=>setLessonOffset(v=>v+PAGE_SIZE)}>Next lesson page</button></div></>}
    </section>}
  </section>
}
