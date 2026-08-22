import { createClient, type SupabaseClient } from '@supabase/supabase-js'

export type AdminMe = {
  user: { id: string; email?: string }
  role: { key: string; name: string }
  permissions: string[]
  mfa: { currentLevel?: string; nextLevel?: string }
}

export function createAdminClient() {
  const url = import.meta.env.VITE_SUPABASE_URL as string
  const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string
  if (!url || !key) throw new Error('Missing Supabase public configuration')
  return createClient(url, key)
}

export async function adminApi(client: SupabaseClient, action: string, body: Record<string, unknown> = {}) {
  const { data: { session } } = await client.auth.getSession()
  if (!session) throw new Error('Authentication required')
  const url = `${client.supabaseUrl}/functions/v1/mela-admin`
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${session.access_token}`,
      apikey: import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string,
      'Content-Type': 'application/json',
      'x-request-id': crypto.randomUUID(),
    },
    body: JSON.stringify({ action, ...body }),
  })
  const data = await response.json().catch(() => ({ error: 'Invalid admin API response' }))
  if (!response.ok || data?.error) throw Object.assign(new Error(data?.error || 'Admin request failed'), { code: data?.code })
  return data
}

export async function getAdminMe(client: SupabaseClient): Promise<AdminMe> {
  const data = await adminApi(client, 'dashboard')
  const admin = data.admin || {}
  return {
    user: { id: admin.id, email: admin.auth_email || admin.email },
    role: { key: admin.role || 'admin', name: admin.role === 'admin' ? 'Administrator' : String(admin.role || 'Administrator') },
    permissions: [],
    mfa: { currentLevel: 'aal2' },
  }
}
