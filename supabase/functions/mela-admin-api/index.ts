import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': Deno.env.get('ADMIN_APP_ORIGIN') ?? 'https://admin.mela.app',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-request-id',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } })

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

  const { data: adminUser, error: adminError } = await adminDb
    .schema('admin')
    .from('admin_users')
    .select('user_id, role_id, active, mfa_required, roles:key(name, key)')
    .eq('user_id', user.id)
    .eq('active', true)
    .maybeSingle()

  if (adminError || !adminUser) return json({ error: 'Admin access denied' }, 403)

  // Require AAL2 when MFA is required. The dashboard never grants access merely from a role row.
  const { data: assurance } = await caller.auth.mfa.getAuthenticatorAssuranceLevel()
  if (adminUser.mfa_required && assurance?.currentLevel !== 'aal2') {
    return json({ error: 'MFA required', code: 'MFA_REQUIRED' }, 403)
  }

  const { data: rolePermissions } = await adminDb
    .schema('admin')
    .from('role_permissions')
    .select('permissions:key')
    .eq('role_id', adminUser.role_id)

  const permissions = (rolePermissions ?? []).map((row: any) => row.permissions?.key).filter(Boolean)
  const role = (adminUser as any).roles
  const requestId = req.headers.get('x-request-id') ?? crypto.randomUUID()
  const body = await req.json().catch(() => ({}))
  const action = body.action ?? 'me'

  if (action === 'me') {
    return json({ user: { id: user.id, email: user.email }, role, permissions, mfa: assurance })
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
    const { data, error } = await adminDb.schema('admin').from('access_requests').select('*, roles:key(name,key)').order('created_at', { ascending: false }).limit(100)
    if (error) return json({ error: error.message }, 500)
    return json({ data })
  }

  if (action === 'audit.append') {
    if (!permissions.includes('authorization.manage')) return json({ error: 'Permission denied' }, 403)
    const record = {
      actor_user_id: user.id,
      actor_role: role?.key ?? null,
      action: body.audit?.action ?? 'admin.action',
      target_schema: body.audit?.target_schema ?? null,
      target_table: body.audit?.target_table ?? null,
      target_id: body.audit?.target_id ?? null,
      before_data: body.audit?.before_data ?? null,
      after_data: body.audit?.after_data ?? null,
      metadata: { ...(body.audit?.metadata ?? {}), source: 'mela-central-dashboard' },
      request_id: requestId,
    }
    const { error } = await adminDb.schema('admin').from('audit_log').insert(record)
    if (error) return json({ error: error.message }, 500)
    return json({ ok: true })
  }

  return json({ error: 'Unknown admin action' }, 400)
})
