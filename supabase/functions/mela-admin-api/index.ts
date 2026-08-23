import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2'

const cors = { 'Access-Control-Allow-Origin': Deno.env.get('ADMIN_APP_ORIGIN') ?? 'https://mela-central-dashboard.netlify.app', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-request-id', 'Access-Control-Allow-Methods': 'POST, OPTIONS' }
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } })
const safeCount = async (db: any, table: string, column = 'id') => {
  const { count, error } = await db.from(table).select(column, { count: 'exact', head: true })
  return error ? null : count
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405)
  const authHeader = req.headers.get('Authorization')
  if (!authHeader?.startsWith('Bearer ')) return json({ error: 'Authentication required' }, 401)

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  const caller = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authHeader } } })
  const adminDb = createClient(supabaseUrl, serviceKey)
  const { data: { user }, error: userError } = await caller.auth.getUser()
  if (userError || !user) return json({ error: 'Invalid session' }, 401)

  const { data: adminUser, error: adminError } = await adminDb.schema('admin').from('admin_users').select('user_id, role_id, active, mfa_required').eq('user_id', user.id).eq('active', true).maybeSingle()
  if (adminError || !adminUser) return json({ error: 'Admin access denied' }, 403)
  const { data: role, error: roleError } = await adminDb.schema('admin').from('roles').select('key,name').eq('id', adminUser.role_id).single()
  if (roleError || !role) return json({ error: 'Admin role is invalid' }, 403)
  const { data: assurance } = await caller.auth.mfa.getAuthenticatorAssuranceLevel()
  if (adminUser.mfa_required && assurance?.currentLevel !== 'aal2') return json({ error: 'MFA required', code: 'MFA_REQUIRED' }, 403)

  const { data: rolePermissions, error: permissionError } = await adminDb.schema('admin').from('role_permissions').select('permission_id').eq('role_id', adminUser.role_id)
  if (permissionError) return json({ error: 'Permission resolution failed' }, 500)
  const ids = (rolePermissions ?? []).map((row: any) => row.permission_id)
  const { data: permissionRows } = ids.length ? await adminDb.schema('admin').from('permissions').select('key').in('id', ids) : { data: [] as any[] }
  const permissions = (permissionRows ?? []).map((row: any) => row.key).filter(Boolean)

  const requestId = req.headers.get('x-request-id') ?? crypto.randomUUID()
  const body = await req.json().catch(() => ({}))
  const action = body.action ?? 'me'
  const canReadOperations = permissions.includes('dashboard.read') || permissions.includes('platform.read') || role.key === 'super_admin'
  const canManageFinance = permissions.includes('finance.manage') || role.key === 'super_admin'

  const appendAudit = async (audit: any) => {
    await adminDb.schema('admin').from('audit_log').insert({
      actor_user_id: user.id,
      actor_role: role.key,
      action: audit.action,
      target_schema: audit.target_schema ?? 'public',
      target_table: audit.target_table ?? null,
      target_id: audit.target_id ?? null,
      before_data: audit.before_data ?? null,
      after_data: audit.after_data ?? null,
      metadata: { ...(audit.metadata ?? {}), source: 'mela-central-dashboard' },
      request_id: requestId
    })
  }

  if (action === 'me') return json({ user: { id: user.id, email: user.email }, role, permissions, mfa: assurance })

  if (action === 'dashboard' || action === 'queues') {
    if (!canReadOperations) return json({ error: 'Permission denied' }, 403)
    const tables = ['profiles','payments','payout_requests','employer_registrations','mentor_verifications','content_reports']
    const counts = await Promise.all(tables.map(async t => [t, await safeCount(adminDb, t)]))
    const metrics: Record<string, unknown> = { table_counts: Object.fromEntries(counts) }
    if (action === 'dashboard') return json({ metrics, generated_at: new Date().toISOString() })

    const queues: Record<string, unknown[]> = {}
    const queueSpecs: [string,string,string][] = [
      ['employer_registrations','employer_registrations','status'],
      ['mentor_verifications','mentor_verifications','status'],
      ['reports','content_reports','status'],
      ['payouts','payout_requests','status'],
      ['proctor_reviews','assessment_attempts','status'],
      ['arena_integrity','arena_matches','status'],
    ]
    for (const [key, table, statusColumn] of queueSpecs) {
      const { data } = await adminDb.from(table).select('*').in(statusColumn, ['pending','queued','review','review_required','flagged','failed']).order('created_at', { ascending: false }).limit(50)
      queues[key] = data ?? []
    }
    return json(queues)
  }

  if (action === 'commission.list') {
    if (!canManageFinance) return json({ error: 'Permission denied' }, 403)
    const limit = Math.min(Math.max(Number(body.limit ?? 50), 1), 200)
    let query = adminDb.from('invitation_commissions').select('*').order('created_at', { ascending: false }).limit(limit)
    if (body.status) query = query.eq('status', body.status)
    if (body.search) {
      const search = String(body.search).trim().replace(/[%_]/g, '')
      if (search) query = query.or(`invitation_code.ilike.%${search}%,transaction_reference.ilike.%${search}%`)
    }
    const { data, error } = await query
    if (error) return json({ error: error.message }, 500)
    return json({ data: data ?? [] })
  }

  if (action === 'commission.inspect') {
    if (!canManageFinance) return json({ error: 'Permission denied' }, 403)
    const commissionId = String(body.commission_id ?? '')
    if (!commissionId) return json({ error: 'Commission ID is required' }, 400)
    const { data, error } = await adminDb.from('invitation_commissions').select('*').eq('id', commissionId).maybeSingle()
    if (error) return json({ error: error.message }, 500)
    if (!data) return json({ error: 'Commission not found' }, 404)
    return json({ data })
  }

  if (action === 'commission.cancel') {
    if (!canManageFinance) return json({ error: 'Permission denied' }, 403)
    const commissionId = String(body.commission_id ?? '')
    const reason = String(body.reason ?? '').trim()
    if (!commissionId || !reason) return json({ error: 'Commission ID and cancellation reason are required' }, 400)
    if (reason.length > 500) return json({ error: 'Cancellation reason must be 500 characters or fewer' }, 400)
    const { data: existing, error: readError } = await adminDb.from('invitation_commissions').select('*').eq('id', commissionId).maybeSingle()
    if (readError) return json({ error: readError.message }, 500)
    if (!existing) return json({ error: 'Commission not found' }, 404)
    if (existing.status === 'cancelled') return json({ data: existing, already_cancelled: true })
    if (existing.status === 'paid') return json({ error: 'Paid commissions require a separate reversal workflow' }, 409)
    const { data: updated, error: updateError } = await adminDb.from('invitation_commissions').update({ status: 'cancelled', cancelled_at: new Date().toISOString(), cancellation_reason: reason }).eq('id', commissionId).eq('status', 'pending').select('*').maybeSingle()
    if (updateError) return json({ error: updateError.message }, 500)
    if (!updated) return json({ error: 'Commission changed concurrently; no cancellation performed' }, 409)
    await appendAudit({ action: 'commission.cancel', target_table: 'invitation_commissions', target_id: commissionId, before_data: existing, after_data: updated, metadata: { reason } })
    return json({ data: updated })
  }

  if (action === 'authorization.matrix') {
    if (!permissions.includes('authorization.manage')) return json({ error: 'Permission denied' }, 403)
    const [{ data: roles, error: rolesError }, { data: allPermissions, error: permissionsError }, { data: mappings, error: mappingsError }] = await Promise.all([
      adminDb.schema('admin').from('roles').select('id,key,name,description,is_privileged').order('name'),
      adminDb.schema('admin').from('permissions').select('id,key,name,description').order('key'),
      adminDb.schema('admin').from('role_permissions').select('role_id,permission_id')
    ])
    if (rolesError || permissionsError || mappingsError) return json({ error: 'Authorization matrix unavailable' }, 500)
    return json({ roles, permissions: allPermissions, mappings })
  }

  if (action === 'audit.list') {
    if (!permissions.includes('audit.read')) return json({ error: 'Permission denied' }, 403)
    const limit = Math.min(Math.max(Number(body.limit ?? 50), 1), 200)
    const { data, error } = await adminDb.schema('admin').from('audit_log').select('*').order('created_at', { ascending: false }).limit(limit)
    if (error) return json({ error: error.message }, 500)
    return json({ data })
  }

  if (action === 'access.list') {
    if (!permissions.includes('authorization.manage')) return json({ error: 'Permission denied' }, 403)
    const { data, error } = await adminDb.schema('admin').from('access_requests').select('*').order('created_at', { ascending: false }).limit(100)
    if (error) return json({ error: error.message }, 500)
    return json({ data })
  }

  if (action === 'audit.append') {
    if (!permissions.includes('authorization.manage')) return json({ error: 'Permission denied' }, 403)
    const audit = body.audit ?? {}
    const { error } = await adminDb.schema('admin').from('audit_log').insert({ actor_user_id:user.id, actor_role:role.key, action:audit.action ?? 'admin.action', target_schema:audit.target_schema ?? null, target_table:audit.target_table ?? null, target_id:audit.target_id ?? null, before_data:audit.before_data ?? null, after_data:audit.after_data ?? null, metadata:{ ...(audit.metadata ?? {}), source:'mela-central-dashboard' }, request_id:requestId })
    if (error) return json({ error: error.message }, 500)
    return json({ ok:true })
  }

  return json({ error: 'Unknown admin action' }, 400)
})
