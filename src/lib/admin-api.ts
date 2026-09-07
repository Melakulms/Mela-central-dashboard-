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

export function createAdminClient() {
  const url = import.meta.env.VITE_SUPABASE_URL as string | undefined
  const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string | undefined
  if (!url || !key) throw new Error('Missing Supabase public configuration')

  return createClient(url, key, {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true,
      storageKey: 'mela-central-admin-auth',
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

export async function adminApi(
  client: SupabaseClient,
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
  const { data, error } = await client.functions.invoke('mela-admin-api', {
    body: { action, ...body },
    headers: {
      'x-request-id': requestId,
      Authorization: `Bearer ${session.access_token}`,
    },
  })

  if (error) {
    throw Object.assign(new Error(error.message || 'Administrative request failed'), {
      code: 'ADMIN_API_ERROR',
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

export async function getAdminMe(client: SupabaseClient): Promise<AdminMe> {
  return adminApi(client, 'me')
}
