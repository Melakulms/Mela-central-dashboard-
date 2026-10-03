import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.116.0'

const allowedOrigins = new Set([
  'https://melakulms.github.io',
  'http://localhost:5173',
  'http://127.0.0.1:5173',
])

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
    headers: {
      ...corsFor(req),
      'Content-Type': 'application/json',
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
    },
  })
}

function normalizeUsername(value: unknown) {
  return String(value ?? '').trim().toLowerCase()
}

function validUsername(username: string) {
  return /^[a-z0-9][a-z0-9._-]{2,31}$/.test(username)
}

function validPassword(password: string) {
  return password.length >= 12 && /[A-Z]/.test(password) && /[a-z]/.test(password) && /\d/.test(password)
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

function clientAddress(req: Request) {
  const forwarded = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim()
  return forwarded || req.headers.get('cf-connecting-ip')?.trim() || req.headers.get('x-real-ip')?.trim() || 'unknown'
}

async function consumeRateLimit(admin: any, keyHash: string, limit: number, windowSeconds: number) {
  const { data, error } = await admin.rpc('consume_beta_auth_rate_limit', {
    p_key_hash: keyHash,
    p_limit: limit,
    p_window_seconds: windowSeconds,
  })
  if (error) throw error
  return data === true
}

async function enforceRateLimits(admin: any, req: Request, action: string, username: string) {
  const address = clientAddress(req)
  const ipKey = await sha256Hex(`beta-auth|${action}|ip|${address}`)
  const subjectKey = await sha256Hex(`beta-auth|${action}|subject|${address}|${username}`)
  const [ipAllowed, subjectAllowed] = await Promise.all([
    consumeRateLimit(admin, ipKey, action === 'signup' ? 30 : 20, 600),
    consumeRateLimit(admin, subjectKey, action === 'signup' ? 8 : 6, 600),
  ])
  return ipAllowed && subjectAllowed
}

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin')
  if (origin && !allowedOrigins.has(origin)) return json(req, { error: 'Origin is not allowed.' }, 403)
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsFor(req) })
  if (req.method !== 'POST') return json(req, { error: 'Method not allowed.' }, 405)

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    if (!supabaseUrl || !serviceKey) return json(req, { error: 'Authentication service is unavailable.' }, 503)

    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    })

    const { data: flag, error: flagError } = await admin
      .from('platform_feature_flags')
      .select('enabled,maintenance_message')
      .eq('feature_key', 'beta_access')
      .maybeSingle()

    if (flagError) return json(req, { error: 'Beta access status is unavailable.' }, 503)
    if (!flag?.enabled) return json(req, { error: flag?.maintenance_message || 'Beta access is temporarily unavailable.' }, 503)

    const body = await req.json().catch(() => null)
    if (!body || typeof body !== 'object' || Array.isArray(body)) return json(req, { error: 'A JSON object is required.' }, 400)
    const action = String((body as any).action ?? '')

    if (action === 'status') return json(req, { enabled: true, mode: 'invite_only', requires_email: false })

    if (action === 'signup') {
      const username = normalizeUsername((body as any).username)
      const fullName = String((body as any).full_name ?? '').trim()
      const password = String((body as any).password ?? '')
      const accessCode = String((body as any).access_code ?? '').trim()

      if (!validUsername(username)) return json(req, { error: 'Username must be 3–32 characters using letters, numbers, dot, dash, or underscore.' }, 400)
      if (fullName.length < 2 || fullName.length > 100) return json(req, { error: 'Please enter your full name.' }, 400)
      if (!validPassword(password)) return json(req, { error: 'Password must be at least 12 characters and include uppercase, lowercase, and a number.' }, 400)
      if (accessCode.length < 16 || accessCode.length > 200) return json(req, { error: 'The beta access code is invalid or expired.' }, 400)
      if (!(await enforceRateLimits(admin, req, action, username))) {
        return json(req, { error: 'Too many beta signup attempts. Please wait 10 minutes and try again.' }, 429)
      }

      const existing = await admin.from('profiles').select('id').eq('username', username).maybeSingle()
      if (existing.data) return json(req, { error: 'That username is already in use.' }, 409)
      if (existing.error) return json(req, { error: 'Unable to validate username.' }, 500)

      const codeHash = await sha256Hex(accessCode)
      const now = new Date().toISOString()
      const { data: invite, error: inviteError } = await admin
        .from('beta_access_invites')
        .update({ used_at: now })
        .eq('code_hash', codeHash)
        .is('used_at', null)
        .is('revoked_at', null)
        .gt('expires_at', now)
        .select('id,role')
        .maybeSingle()

      if (inviteError || !invite) return json(req, { error: 'The beta access code is invalid, expired, or already used.' }, 400)

      const syntheticEmail = `${username}@beta.mela.invalid`
      const { data: created, error: createError } = await admin.auth.admin.createUser({
        email: syntheticEmail,
        password,
        email_confirm: true,
        user_metadata: {
          full_name: fullName,
          role: invite.role,
          preferred_language: 'English',
          username,
          beta_account: true,
        },
      })

      if (createError || !created.user) {
        await admin.from('beta_access_invites').update({ used_at: null }).eq('id', invite.id).is('used_by', null)
        return json(req, { error: createError?.message?.includes('already') ? 'That username is already in use.' : 'Could not create the beta account.' }, createError?.message?.includes('already') ? 409 : 500)
      }

      const userId = created.user.id
      const recoveryCode = `MELA-R-${randomCode(24)}`
      const recoveryHash = await sha256Hex(recoveryCode)

      const profileUpdate = await admin.from('profiles').update({ username, auth_provider: 'beta_invite' }).eq('id', userId)
      const recoveryInsert = await admin.from('beta_auth_recovery').insert({ user_id: userId, recovery_hash: recoveryHash })
      const inviteFinalize = await admin.from('beta_access_invites').update({ used_by: userId }).eq('id', invite.id).is('used_by', null)

      if (profileUpdate.error || recoveryInsert.error || inviteFinalize.error) {
        await admin.auth.admin.deleteUser(userId).catch(() => undefined)
        await admin.from('beta_access_invites').update({ used_at: null, used_by: null }).eq('id', invite.id)
        return json(req, { error: 'Could not finish creating the beta account.' }, 500)
      }

      return json(req, {
        created: true,
        username,
        role: invite.role,
        recovery_code: recoveryCode,
        recovery_notice: 'Save this recovery code somewhere private. It is required to reset your beta password and is shown only now.',
      }, 201)
    }

    if (action === 'reset_password') {
      const username = normalizeUsername((body as any).username)
      const recoveryCode = String((body as any).recovery_code ?? '').trim()
      const newPassword = String((body as any).new_password ?? '')
      if (!validUsername(username) || recoveryCode.length < 20 || !validPassword(newPassword)) {
        return json(req, { error: 'The recovery details are invalid.' }, 400)
      }
      if (!(await enforceRateLimits(admin, req, action, username))) {
        return json(req, { error: 'Too many recovery attempts. Please wait 10 minutes and try again.' }, 429)
      }

      const { data: profile } = await admin.from('profiles').select('id').eq('username', username).maybeSingle()
      if (!profile?.id) return json(req, { error: 'The recovery details are invalid.' }, 400)
      const { data: recovery } = await admin.from('beta_auth_recovery').select('recovery_hash').eq('user_id', profile.id).maybeSingle()
      if (!recovery?.recovery_hash) return json(req, { error: 'The recovery details are invalid.' }, 400)

      const suppliedHash = await sha256Hex(recoveryCode)
      if (suppliedHash !== recovery.recovery_hash) return json(req, { error: 'The recovery details are invalid.' }, 400)

      const { error: passwordError } = await admin.auth.admin.updateUserById(profile.id, { password: newPassword })
      if (passwordError) return json(req, { error: 'Could not reset the beta password.' }, 500)

      const nextRecoveryCode = `MELA-R-${randomCode(24)}`
      const nextHash = await sha256Hex(nextRecoveryCode)
      const { error: rotateError } = await admin.from('beta_auth_recovery').update({ recovery_hash: nextHash, rotated_at: new Date().toISOString() }).eq('user_id', profile.id)
      if (rotateError) return json(req, { error: 'Password changed, but the recovery code could not be rotated. Contact the platform administrator.' }, 500)

      return json(req, {
        reset: true,
        recovery_code: nextRecoveryCode,
        recovery_notice: 'Your old recovery code is no longer valid. Save this new code somewhere private.',
      })
    }

    return json(req, { error: 'Unknown beta-auth action.' }, 400)
  } catch {
    return json(req, { error: 'The beta authentication request could not be completed.' }, 500)
  }
})
