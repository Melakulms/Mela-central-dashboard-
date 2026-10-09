import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.116.0'

const DEFAULT_ORIGIN = 'https://melakulms.github.io'
const ENTITY_TYPES = new Set(['chapter', 'material', 'question', 'translation', 'book', 'program_seed'])
const LANGUAGES = new Set(['en', 'am', 'om', 'ti', 'so'])
const EDITABLE_STATUSES = new Set(['draft', 'rejected'])

const limitOf = (value: unknown, max = 200) => {
  const n = Number(value ?? 50)
  return Number.isFinite(n) ? Math.min(Math.max(Math.trunc(n), 1), max) : 50
}
const offsetOf = (value: unknown) => {
  const n = Number(value ?? 0)
  return Number.isFinite(n) ? Math.max(Math.trunc(n), 0) : 0
}
const clean = (value: unknown, max = 300) => String(value ?? '').trim().slice(0, max)
const objectPayload = (value: unknown) => value && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : null
const validUuid = (value: string) => /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin')
  const allowedOrigins = new Set([
    DEFAULT_ORIGIN,
    'https://central-dashboard-gamma.vercel.app',
    Deno.env.get('ADMIN_APP_ORIGIN'),
  ].filter(Boolean) as string[])
  const responseCors = {
    'Access-Control-Allow-Origin': origin && allowedOrigins.has(origin) ? origin : DEFAULT_ORIGIN,
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-request-id',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin',
  }
  const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
    status,
    headers: { ...responseCors, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  })
  if (origin && !allowedOrigins.has(origin)) return json({ error: 'Origin is not allowed' }, 403)
  if (req.method === 'OPTIONS') return new Response('ok', { headers: responseCors })
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405)

  const requestId = req.headers.get('x-request-id') ?? crypto.randomUUID()
  const authHeader = req.headers.get('Authorization')
  if (!authHeader?.startsWith('Bearer ')) return json({ error: 'Authentication required' }, 401)

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const caller = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false },
    })
    const adminDb = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    })

    const { data: { user }, error: userError } = await caller.auth.getUser()
    if (userError || !user) return json({ error: 'Invalid session' }, 401)

    const { data: adminUser, error: adminError } = await adminDb.schema('admin').from('admin_users')
      .select('user_id, role_id, active, mfa_required')
      .eq('user_id', user.id).eq('active', true).maybeSingle()
    if (adminError || !adminUser) return json({ error: 'Admin access denied' }, 403)

    const { data: role, error: roleError } = await adminDb.schema('admin').from('roles')
      .select('key,name').eq('id', adminUser.role_id).single()
    if (roleError || !role) return json({ error: 'Admin role is invalid' }, 403)

    const { data: assurance, error: assuranceError } = await caller.auth.mfa.getAuthenticatorAssuranceLevel(authHeader.slice(7))
    if (assuranceError) return json({ error: 'Unable to verify session assurance' }, 401)
    if (adminUser.mfa_required && assurance?.currentLevel !== 'aal2') {
      return json({ error: 'MFA required', code: 'MFA_REQUIRED' }, 403)
    }

    const { data: rolePermissions, error: rolePermissionsError } = await adminDb.schema('admin').from('role_permissions')
      .select('permission_id').eq('role_id', adminUser.role_id)
    if (rolePermissionsError) return json({ error: 'Permission resolution failed' }, 500)
    const permissionIds = (rolePermissions ?? []).map((row: any) => row.permission_id)
    const permissionResult = permissionIds.length
      ? await adminDb.schema('admin').from('permissions').select('key').in('id', permissionIds)
      : { data: [] as any[], error: null }
    if (permissionResult.error) return json({ error: 'Permission resolution failed' }, 500)
    const permissions = (permissionResult.data ?? []).map((row: any) => row.key).filter(Boolean)
    const isSuper = role.key === 'super_admin'
    if (!isSuper && !permissions.includes('content.manage')) return json({ error: 'Permission denied' }, 403)

    const body = await req.json().catch(() => null)
    if (!body || typeof body !== 'object' || Array.isArray(body) || typeof (body as any).action !== 'string') {
      return json({ error: 'A JSON object with an action is required' }, 400)
    }
    const action = String((body as any).action)

    const audit = async (actionName: string, targetId: string, beforeData: unknown, afterData: unknown, metadata: Record<string, unknown> = {}) => {
      const { error } = await adminDb.schema('admin').from('audit_log').insert({
        actor_user_id: user.id,
        actor_role: role.key,
        action: actionName,
        target_schema: 'admin',
        target_table: 'content_drafts',
        target_id: targetId,
        before_data: beforeData,
        after_data: afterData,
        metadata,
        request_id: requestId,
      })
      if (error) throw error
    }

    if (action === 'overview') {
      const [summary, gaps, translations, chapterReviews, questionBatches] = await Promise.all([
        adminDb.schema('admin').from('content_quality_summary').select('*').single(),
        adminDb.schema('admin').from('content_program_inventory').select('*')
          .eq('active', true).eq('has_content', false).order('stage_key').order('grade_level', { nullsFirst: false }).order('title').limit(100),
        adminDb.schema('admin').from('content_translation_inventory').select('*').order('source').order('language_code').order('review_status'),
        adminDb.from('mela_chapter_review_queue').select('id,chapter_id,program_key,grade_level,subject_key,chapter_number,chapter_title,source_state,review_type,priority,status,reviewer_requirement,assigned_to,updated_at')
          .order('priority', { ascending: false }).order('updated_at', { ascending: true }).limit(50),
        adminDb.from('mela_question_review_batches').select('program_key,grade_level,subject_title,target_question_count,generated_question_count,deterministic_validated_count,educator_verified_count,review_status,assigned_to,reviewed_by,reviewed_at,updated_at')
          .order('updated_at', { ascending: true }).limit(50),
      ])
      for (const result of [summary, gaps, translations, chapterReviews, questionBatches]) {
        if (result.error) return json({ error: 'Unable to load content studio overview' }, 500)
      }
      return json({
        summary: summary.data,
        empty_programs: gaps.data ?? [],
        translations: translations.data ?? [],
        chapter_reviews: chapterReviews.data ?? [],
        question_review_batches: questionBatches.data ?? [],
        generated_at: new Date().toISOString(),
      })
    }

    if (action === 'courses.list') {
      const limit = limitOf((body as any).limit, 100)
      const offset = offsetOf((body as any).offset)
      let query = adminDb.schema('admin').from('course_content_inventory').select('*', { count: 'exact' })
        .order('featured_rank', { nullsFirst: false }).order('id').range(offset, offset + limit - 1)
      const search = clean((body as any).search, 120).replace(/[,%()]/g, ' ')
      if (search) query = query.ilike('title', `%${search}%`)
      if ((body as any).missing_only === true) query = query.eq('content_available', false)
      const { data, error, count } = await query
      if (error) return json({ error: 'Unable to load course inventory' }, 500)
      return json({ data: data ?? [], total: count ?? 0, offset, limit })
    }

    if (action === 'courses.lessons') {
      const courseId = clean((body as any).course_id, 80)
      if (!validUuid(courseId)) return json({ error: 'Valid course ID is required' }, 400)
      const limit = limitOf((body as any).limit, 100)
      const offset = offsetOf((body as any).offset)
      const { data, error, count } = await adminDb.from('course_lessons')
        .select('id,course_id,module_title,module_position,title,lesson_position,duration_minutes,is_preview,content_text', { count: 'exact' })
        .eq('course_id', courseId).order('module_position').order('lesson_position').order('id').range(offset, offset + limit - 1)
      if (error) return json({ error: 'Unable to load course lessons' }, 500)
      return json({ data: data ?? [], total: count ?? 0, offset, limit })
    }

    if (action === 'review.queue') {
      const kind = clean((body as any).kind, 20)
      if (!['chapters', 'questions'].includes(kind)) return json({ error: 'Choose chapters or questions' }, 400)
      const grade = (body as any).grade_level
      if (grade != null && (!Number.isInteger(grade) || grade < 1 || grade > 12)) return json({ error: 'Grade must be 1–12' }, 400)
      const limit = limitOf((body as any).limit, 100)
      const offset = offsetOf((body as any).offset)
      const program = clean((body as any).program_key, 160)
      let query = kind === 'chapters'
        ? adminDb.from('mela_chapter_review_queue').select('id,chapter_id,program_key,grade_level,subject_key,chapter_number,chapter_title,source_state,review_type,priority,status,reviewer_requirement,assigned_to,updated_at', { count: 'exact' }).order('priority', { ascending: false }).order('id')
        : adminDb.from('mela_question_review_batches').select('program_key,grade_level,subject_title,target_question_count,generated_question_count,deterministic_validated_count,educator_verified_count,review_status,assigned_to,reviewed_by,reviewed_at,updated_at', { count: 'exact' }).order('grade_level').order('program_key')
      if (grade != null) query = query.eq('grade_level', grade)
      if (program) query = query.eq('program_key', program)
      const { data, error, count } = await query.range(offset, offset + limit - 1)
      if (error) return json({ error: 'Unable to load qualified-review queue' }, 500)
      return json({ data: data ?? [], total: count ?? 0, offset, limit })
    }

    if (action === 'programs.list') {
      const limit = limitOf((body as any).limit)
      const offset = offsetOf((body as any).offset)
      let query = adminDb.schema('admin').from('content_program_inventory').select('*', { count: 'exact' })
        .order('stage_key').order('grade_level', { nullsFirst: false }).order('title').order('program_key').range(offset, offset + limit - 1)
      const stage = clean((body as any).stage_key, 80)
      const search = clean((body as any).search, 120).replace(/[,%()]/g, ' ')
      const grade = (body as any).grade_level
      if (grade != null && (!Number.isInteger(grade) || grade < 1 || grade > 12)) return json({ error: 'Grade must be 1–12' }, 400)
      if (grade != null) query = query.eq('grade_level', grade)
      if (stage) query = query.eq('stage_key', stage)
      if ((body as any).empty_only === true) query = query.eq('has_content', false)
      if (search) query = query.or(`program_key.ilike.%${search}%,title.ilike.%${search}%,subject_title.ilike.%${search}%`)
      const { data, error, count } = await query
      if (error) return json({ error: 'Unable to load program inventory' }, 500)
      return json({ data: data ?? [], total: count ?? 0, offset, limit })
    }

    if (action === 'drafts.list') {
      const limit = limitOf((body as any).limit)
      const offset = offsetOf((body as any).offset)
      let query = adminDb.schema('admin').from('content_drafts').select('*', { count: 'exact' })
        .order('updated_at', { ascending: false }).order('id').range(offset, offset + limit - 1)
      const status = clean((body as any).status, 30)
      const entityType = clean((body as any).entity_type, 40)
      const programKey = clean((body as any).program_key, 160)
      if (status) query = query.eq('status', status)
      if (entityType) query = query.eq('entity_type', entityType)
      if (programKey) query = query.eq('program_key', programKey)
      const { data, error, count } = await query
      if (error) return json({ error: 'Unable to load content drafts' }, 500)
      return json({ data: data ?? [], total: count ?? 0, offset, limit })
    }

    if (action === 'draft.save') {
      const draftId = clean((body as any).draft_id, 80)
      const entityType = clean((body as any).entity_type, 40)
      const targetId = clean((body as any).target_id, 80)
      const programKey = clean((body as any).program_key, 160)
      const languageCode = clean((body as any).language_code || 'en', 10)
      const title = clean((body as any).title, 300)
      const payload = objectPayload((body as any).payload)
      if (!ENTITY_TYPES.has(entityType)) return json({ error: 'Invalid content entity type' }, 400)
      if (!LANGUAGES.has(languageCode)) return json({ error: 'Invalid language code' }, 400)
      if (!title) return json({ error: 'Draft title is required' }, 400)
      if (!payload) return json({ error: 'Draft payload must be a JSON object' }, 400)
      if (JSON.stringify(payload).length > 200_000) return json({ error: 'Draft payload is too large' }, 413)
      if (targetId && !validUuid(targetId)) return json({ error: 'Invalid target ID' }, 400)

      if (!draftId) {
        const { data, error } = await adminDb.schema('admin').from('content_drafts').insert({
          entity_type: entityType,
          target_id: targetId || null,
          program_key: programKey || null,
          language_code: languageCode,
          title,
          payload,
          status: 'draft',
          created_by: user.id,
          updated_by: user.id,
        }).select('*').single()
        if (error) return json({ error: 'Unable to create content draft' }, 500)
        await audit('content.draft.create', data.id, null, data, { entity_type: entityType, program_key: programKey || null })
        return json({ data }, 201)
      }

      if (!validUuid(draftId)) return json({ error: 'Invalid draft ID' }, 400)
      const { data: existing, error: readError } = await adminDb.schema('admin').from('content_drafts').select('*').eq('id', draftId).maybeSingle()
      if (readError) return json({ error: 'Unable to read content draft' }, 500)
      if (!existing) return json({ error: 'Content draft not found' }, 404)
      if (!EDITABLE_STATUSES.has(existing.status)) return json({ error: 'Submitted or published drafts cannot be edited directly' }, 409)
      const expectedVersion = Number((body as any).expected_version ?? existing.version)
      if (!Number.isInteger(expectedVersion) || expectedVersion !== existing.version) {
        return json({ error: 'Draft changed; refresh before editing', code: 'STALE_DRAFT' }, 409)
      }
      const { data, error } = await adminDb.schema('admin').from('content_drafts').update({
        entity_type: entityType,
        target_id: targetId || null,
        program_key: programKey || null,
        language_code: languageCode,
        title,
        payload,
        status: 'draft',
        updated_by: user.id,
        submitted_at: null,
        reviewed_by: null,
        reviewed_at: null,
        reviewer_note: null,
        published_at: null,
      }).eq('id', draftId).eq('version', existing.version).select('*').single()
      if (error) return json({ error: 'Unable to save content draft' }, 500)
      await audit('content.draft.update', draftId, existing, data, { entity_type: entityType, program_key: programKey || null })
      return json({ data })
    }

    if (action === 'draft.submit') {
      const draftId = clean((body as any).draft_id, 80)
      if (!validUuid(draftId)) return json({ error: 'Valid draft ID is required' }, 400)
      const { data: existing, error: readError } = await adminDb.schema('admin').from('content_drafts').select('*').eq('id', draftId).maybeSingle()
      if (readError) return json({ error: 'Unable to read content draft' }, 500)
      if (!existing) return json({ error: 'Content draft not found' }, 404)
      if (!EDITABLE_STATUSES.has(existing.status)) return json({ error: 'Only draft or rejected content can be submitted' }, 409)
      if (!existing.payload || !Object.keys(existing.payload).length) return json({ error: 'Draft payload cannot be empty' }, 400)
      if (existing.entity_type === 'material' && existing.payload.course_id != null) {
        const lesson = existing.payload
        if (!validUuid(String(lesson.course_id)) || !clean(lesson.title) || !clean(lesson.module_title)
          || typeof lesson.content_text !== 'string' || lesson.content_text.trim().length < 100
          || !Array.isArray(lesson.objectives) || !lesson.objectives.some((value: unknown) => typeof value === 'string' && value.trim())
          || !['module_position','lesson_position','duration_minutes'].every(key => Number.isInteger(lesson[key]) && lesson[key] > 0)) {
          return json({ error: 'Complete the course lesson title, module, text, objectives, ordering and duration before submitting.' }, 400)
        }
        const { data: course, error: courseError } = await adminDb.from('courses').select('id').eq('id', lesson.course_id).maybeSingle()
        if (courseError) return json({ error: 'Unable to validate the lesson course' }, 500)
        if (!course) return json({ error: 'The lesson course no longer exists' }, 400)
      }
      const { data, error } = await adminDb.schema('admin').from('content_drafts').update({
        status: 'submitted',
        submitted_at: new Date().toISOString(),
        updated_by: user.id,
      }).eq('id', draftId).eq('version', existing.version).select('*').single()
      if (error) return json({ error: 'Unable to submit content draft' }, 500)
      await audit('content.draft.submit', draftId, existing, data, { review_required: true })
      return json({ data, publication_locked: true, message: 'Draft submitted. Publication remains locked until qualified review evidence exists.' })
    }

    if (action === 'draft.archive') {
      const draftId = clean((body as any).draft_id, 80)
      if (!validUuid(draftId)) return json({ error: 'Valid draft ID is required' }, 400)
      const { data: existing, error: readError } = await adminDb.schema('admin').from('content_drafts').select('*').eq('id', draftId).maybeSingle()
      if (readError) return json({ error: 'Unable to read content draft' }, 500)
      if (!existing) return json({ error: 'Content draft not found' }, 404)
      if (existing.status === 'archived') return json({ data: existing })
      const { data, error } = await adminDb.schema('admin').from('content_drafts').update({
        status: 'archived',
        updated_by: user.id,
      }).eq('id', draftId).eq('version', existing.version).select('*').single()
      if (error) return json({ error: 'Unable to archive content draft' }, 500)
      await audit('content.draft.archive', draftId, existing, data)
      return json({ data })
    }

    if (action === 'draft.versions') {
      const draftId = clean((body as any).draft_id, 80)
      if (!validUuid(draftId)) return json({ error: 'Valid draft ID is required' }, 400)
      const { data, error } = await adminDb.schema('admin').from('content_draft_versions')
        .select('id,draft_id,version_no,snapshot,changed_by,change_kind,created_at')
        .eq('draft_id', draftId).order('version_no', { ascending: false }).limit(100)
      if (error) return json({ error: 'Unable to load content draft versions' }, 500)
      return json({ data: data ?? [] })
    }

    return json({ error: 'Unknown content admin action' }, 404)
  } catch (error) {
    console.error('mela-content-admin', error)
    return json({ error: 'Content administration request failed', code: 'CONTENT_ADMIN_FAILED', request_id: requestId }, 500)
  }
})
