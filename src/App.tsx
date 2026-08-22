import { useEffect, useState } from 'react'
import { ShieldCheck, LogOut, RefreshCw, Activity, LockKeyhole } from 'lucide-react'
import type { SupabaseClient } from '@supabase/supabase-js'
import { createAdminClient, getAdminMe, type AdminMe } from './lib/admin-api'

const client: SupabaseClient = createAdminClient()

export default function App() {
  const [me, setMe] = useState<AdminMe | null>(null)
  const [error, setError] = useState<string>('')
  const [loading, setLoading] = useState(true)

  async function load() {
    setLoading(true); setError('')
    try { setMe(await getAdminMe(client)) }
    catch (e) { setMe(null); setError(e instanceof Error ? e.message : 'Admin access denied') }
    finally { setLoading(false) }
  }

  useEffect(() => { load() }, [])

  if (loading) return <main className="center"><RefreshCw className="spin" /><span>Verifying administrator session…</span></main>

  if (!me) return <main className="center"><section className="card"><LockKeyhole size={40}/><h1>MELA Central Admin</h1><p>{error || 'Administrator authentication is required.'}</p><button onClick={() => client.auth.signInWithOAuth({ provider: 'google', options: { redirectTo: window.location.origin } })}>Admin sign in</button></section></main>

  return <main className="app"><aside><div className="brand"><ShieldCheck/> MELA Central</div><nav><a className="active"><Activity size={18}/> Overview</a><a>Users</a><a>Opportunities</a><a>Payments</a><a>Disputes</a><a>Moderation</a><a>Authorization</a><a>Audit Log</a></nav><button className="logout" onClick={() => client.auth.signOut()}><LogOut size={17}/> Sign out</button></aside><section className="content"><header><div><p className="eyebrow">SECURE CONTROL PLANE</p><h1>Platform Overview</h1></div><button onClick={load}><RefreshCw size={17}/> Refresh</button></header><div className="notice"><ShieldCheck size={20}/><div><strong>{me.role.name}</strong><span> · {me.permissions.length} permissions · MFA {me.mfa?.currentLevel === 'aal2' ? 'verified' : 'required'}</span></div></div><section className="grid"><article><span>Administrative identity</span><strong>{me.user.email || me.user.id}</strong></article><article><span>Authorization</span><strong>Server-side enforced</strong></article><article><span>Audit trail</span><strong>Enabled</strong></article><article><span>Admin boundary</span><strong>Separate application</strong></article></section></section></main>
}
