import {
  createClient,
  type AuthChangeEvent,
  type Session,
  type SupabaseClient,
} from '@supabase/supabase-js'

export type AdminMe = {
  user: { id: string; email?: string }
  role: { key: string; name: string }
  permissions: string[]
  mfa: { currentLevel?: string; nextLevel?: string }
}

const LEGACY_ADMIN_STORAGE_KEY = 'mela-central-admin-auth'

export function createAdminClient() {
  const url = import.meta.env.VITE_SUPABASE_URL as string | undefined
  const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string | undefined
  if (!url || !key) throw new Error('Missing Supabase public configuration')

  // Older builds persisted the privileged session under this origin-wide key.
  // Remove it before creating the non-persistent client so an old refresh/access
  // token is not left readable by another application on the shared origin.
  if (typeof window !== 'undefined') {
    try { window.localStorage.removeItem(LEGACY_ADMIN_STORAGE_KEY) } catch { /* storage may be unavailable */ }
  }

  return createClient(url, key, {
    auth: {
      // Administrative bearer tokens must not be left in origin-wide localStorage.
      // Until the admin UI is isolated on its own origin, keep the session in memory
      // so another application served from the same origin cannot read a persisted token.
      persistSession: false,
      autoRefreshToken: true,
      detectSessionInUrl: false,
    },
  })
}

export async function getCurrentSession(client: SupabaseClient): Promise<Session | null> {
  const { data, error } = await client.auth.getSession()
  if (error) throw error
  return data.session ?? null
}

export function subscribeToAuth(
  client: SupabaseClient,
  callback: (event: AuthChangeEvent, session: Session | null) => void,
) {
  const { data } = client.auth.onAuthStateChange(callback)
  return () => data.subscription.unsubscribe()
}

export async function signOutAdmin(client: SupabaseClient) {
  const { error } = await client.auth.signOut({ scope: 'local' })
  if (error) throw error
}

async function invokeAdminFunction(
  client: SupabaseClient,
  functionName: string,
  action: string,
  body: Record<string, unknown> = {},
) {
  const session = await getCurrentSession(client)
  if (!session?.access_token) {
    throw Object.assign(new Error('Authentication required. Please sign in again.'), {
      code: 'AUTH_REQUIRED',
    })
  }

  const requestId = crypto.randomUUID()
  const { data, error } = await client.functions.invoke(functionName, {
    body: { ...body, action },
    headers: {
      'x-request-id': requestId,
      Authorization: `Bearer ${session.access_token}`,
    },
  })

  if (error) {
    const detail = error.context instanceof Response ? await error.context.clone().json().catch(() => null) : null
    throw Object.assign(new Error(detail?.error || error.message || 'Administrative request failed'), {
      code: detail?.code ?? 'ADMIN_API_ERROR',
      cause: error,
    })
  }

  if (data?.error) {
    throw Object.assign(new Error(String(data.error)), {
      code: data.code ?? 'ADMIN_API_ERROR',
    })
  }

  return data
}

export async function adminApi(
  client: SupabaseClient,
  action: string,
  body: Record<string, unknown> = {},
) {
  return invokeAdminFunction(client, 'mela-admin-api', action, body)
}

export async function betaAdminApi(
  client: SupabaseClient,
  action: string,
  body: Record<string, unknown> = {},
) {
  return invokeAdminFunction(client, 'mela-beta-admin', action, body)
}

export async function getAdminMe(client: SupabaseClient): Promise<AdminMe> {
  return adminApi(client, 'me')
}
