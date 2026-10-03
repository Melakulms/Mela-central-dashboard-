import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.116.0'

const allowedOrigins = new Set([
  'https://melakulms.github.io',
  'https://central-dashboard-gamma.vercel.app',
  Deno.env.get('ADMIN_APP_ORIGIN'),
].filter(Boolean) as string[])

const baseCors = {
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

function corsFor(req: Request) {
  const origin = req.headers.get('Origin')
  return {
    ...baseCors,
    'Access-Control-Allow-Origin': origin && allowedOrigins.has(origin) ? origin : 'https://melakulms.github.io',
    'Vary': 'Origin',
  }
}

function json(req: Request, body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsFor(req), 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  })
}

async function sha256Hex(value: string) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value))
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('')
}

function randomCode(bytes = 24) {
  const data = new Uint8Array(bytes)
  crypto.getRandomValues(data)
  let binary = ''
  for (const byte of data) binary += String.fromCharCode(byte)
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '')
}

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin')
  if (origin && !allowedOrigins.has(origin)) return json(req, { error: 'Origin is not allowed.' }, 403)
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsFor(req) })
  if (req.method !== 'POST') return json(req, { error: 'Method not allowed.' }, 405)

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader?.startsWith('Bearer ')) return json(req, { error: 'Authentication required.' }, 401)

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const caller = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false },
    })
    const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } })

    const { data: { user }, error: userError } = await caller.auth.getUser()
    if (userError || !user) return json(req, { error: 'Invalid session.' }, 401)

    const { data: adminUser, error: adminError } = await admin.schema('admin').from('admin_users')
      .select('user_id,role_id,active,mfa_required')
      .eq('user_id', user.id).eq('active', true).maybeSingle()
    if (adminError || !adminUser) return json(req, { error: 'Admin access denied.' }, 403)

    const { data: role, error: roleError } = await admin.schema('admin').from('roles').select('id,key').eq('id', adminUser.role_id).maybeSingle()
    if (roleError || !role) return json(req, { error: 'Admin role is invalid.' }, 403)

    const { data: assurance, error: assuranceError } = await caller.auth.mfa.getAuthenticatorAssuranceLevel(authHeader.slice(7))
    if (assuranceError) return json(req, { error: 'Unable to verify session assurance.' }, 401)
    if (adminUser.mfa_required && assurance?.currentLevel !== 'aal2') return json(req, { error: 'MFA required.', code: 'MFA_REQUIRED' }, 403)

    const { data: mappings, error: mappingError } = await admin.schema('admin').from('role_permissions').select('permission_id').eq('role_id', adminUser.role_id)
    if (mappingError) return json(req, { error: 'Permission resolution failed.' }, 500)
    const ids = (mappings ?? []).map((row: any) => row.permission_id)
    const { data: permissionRows, error: permissionError } = ids.length
      ? await admin.schema('admin').from('permissions').select('key').in('id', ids)
      : { data: [] as any[], error: null }
    if (permissionError) return json(req, { error: 'Permission resolution failed.' }, 500)
    const permissions = new Set((permissionRows ?? []).map((row: any) => row.key))
    if (role.key !== 'super_admin' && !permissions.has('users.manage')) return json(req, { error: 'Permission denied.' }, 403)

    const body = await req.json().catch(() => null)
    if (!body || typeof body !== 'object' || Array.isArray(body)) return json(req, { error: 'A JSON object is required.' }, 400)
    const action = String((body as any).action ?? '')

    if (action === 'invite.create') {
      const requestedRole = String((body as any).role ?? 'student')
      const allowedRoles = new Set(['student', 'parent', 'teacher', 'company'])
      if (!allowedRoles.has(requestedRole)) return json(req, { error: 'Invalid beta role.' }, 400)
      const daysRaw = Number((body as any).expires_in_days ?? 7)
      const days = Number.isFinite(daysRaw) ? Math.min(Math.max(Math.trunc(daysRaw), 1), 30) : 7
      const note = String((body as any).note ?? '').trim()
      if (note.length > 500) return json(req, { error: 'Invite note must be 500 characters or fewer.' }, 400)

      const code = `MELA-B-${randomCode(24)}`
      const codeHash = await sha256Hex(code)
      const expiresAt = new Date(Date.now() + days * 86_400_000).toISOString()
      const { data, error } = await admin.from('beta_access_invites').insert({
        code_hash: codeHash,
        role: requestedRole,
        expires_at: expiresAt,
        created_by: user.id,
        note: note || null,
      }).select('id,role,expires_at,note,created_at').single()
      if (error) return json(req, { error: 'Could not create beta invite.' }, 500)
      return json(req, { data: { ...data, access_code: code, access_code_notice: 'Copy this code now. Only its hash is stored.' } }, 201)
    }

    if (action === 'invite.list') {
      const limitRaw = Number((body as any).limit ?? 50)
      const limit = Number.isFinite(limitRaw) ? Math.min(Math.max(Math.trunc(limitRaw), 1), 100) : 50
      const { data, error } = await admin.from('beta_access_invites')
        .select('id,role,expires_at,used_at,used_by,revoked_at,created_by,note,created_at')
        .order('created_at', { ascending: false }).limit(limit)
      if (error) return json(req, { error: 'Could not load beta invites.' }, 500)
      return json(req, { data: data ?? [] })
    }

    if (action === 'invite.revoke') {
      const id = String((body as any).invite_id ?? '')
      if (!id) return json(req, { error: 'Invite ID is required.' }, 400)
      const { data: existing, error: readError } = await admin.from('beta_access_invites').select('id,used_at,revoked_at').eq('id', id).maybeSingle()
      if (readError) return json(req, { error: 'Could not read beta invite.' }, 500)
      if (!existing) return json(req, { error: 'Beta invite not found.' }, 404)
      if (existing.used_at) return json(req, { error: 'Used beta invites cannot be revoked.' }, 409)
      if (existing.revoked_at) return json(req, { data: existing, already_revoked: true })
      const { data, error } = await admin.from('beta_access_invites').update({ revoked_at: new Date().toISOString() }).eq('id', id).select('id,revoked_at').single()
      if (error) return json(req, { error: 'Could not revoke beta invite.' }, 500)
      return json(req, { data })
    }

    return json(req, { error: 'Unknown beta-admin action.' }, 400)
  } catch {
    return json(req, { error: 'The beta-admin request could not be completed.' }, 500)
  }
})
