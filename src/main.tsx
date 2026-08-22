import React, { useEffect, useMemo, useState } from 'react'
import { createRoot } from 'react-dom/client'
import { createClient, type Session, type User } from '@supabase/supabase-js'
import { ShieldCheck, LayoutDashboard, Users, LockKeyhole, FileClock, Settings, LogOut, AlertTriangle, RefreshCw } from 'lucide-react'
import './styles.css'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL as string | undefined
const supabaseKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string | undefined
const adminFunctionUrl = import.meta.env.VITE_ADMIN_API_URL as string | undefined
const supabase = supabaseUrl && supabaseKey ? createClient(supabaseUrl, supabaseKey) : null

const nav = [
  { id: 'overview', label: 'Overview', icon: LayoutDashboard },
  { id: 'users', label: 'Users', icon: Users },
  { id: 'access', label: 'Authorization', icon: LockKeyhole },
  { id: 'audit', label: 'Audit Log', icon: FileClock },
  { id: 'settings', label: 'System', icon: Settings },
] as const

type Section = typeof nav[number]['id']
type AdminState = { allowed: boolean; role?: { key:string; name:string }; permissions: string[]; mfaRequired: boolean; mfaVerified: boolean }

async function callAdmin(action: string, body: Record<string, unknown> = {}) {
  if (!supabase || !adminFunctionUrl) throw new Error('Admin API is not configured.')
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) throw new Error('Authentication required.')
  const response = await fetch(adminFunctionUrl, { method:'POST', headers:{ Authorization:`Bearer ${session.access_token}`, 'Content-Type':'application/json', 'x-request-id':crypto.randomUUID() }, body:JSON.stringify({ action, ...body }) })
  const payload = await response.json().catch(()=>({ error:'Invalid server response' }))
  if (!response.ok) throw Object.assign(new Error(payload.error ?? 'Admin request failed'), { code: payload.code })
  return payload
}

function App() {
  const [session, setSession] = useState<Session | null>(null)
  const [user, setUser] = useState<User | null>(null)
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)
  const [section, setSection] = useState<Section>('overview')
  const [admin, setAdmin] = useState<AdminState | null>(null)
  const [mfaCode, setMfaCode] = useState('')
  const [mfaFactorId, setMfaFactorId] = useState<string | null>(null)

  useEffect(() => {
    if (!supabase) return
    supabase.auth.getSession().then(({ data }) => { setSession(data.session); setUser(data.session?.user ?? null) })
    const { data: listener } = supabase.auth.onAuthStateChange((_event, next) => { setSession(next); setUser(next?.user ?? null) })
    return () => listener.subscription.unsubscribe()
  }, [])

  const loadAdmin = async () => {
    if (!session || !supabase) { setAdmin(null); return }
    try {
      const { data: assurance } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel()
      if (assurance?.currentLevel !== 'aal2') {
        const { data: factors } = await supabase.auth.mfa.listFactors()
        const factor = factors?.totp?.find((item:any)=>item.status==='verified')
        setMfaFactorId(factor?.id ?? null)
      }
      const result = await callAdmin('me')
      setAdmin({ allowed:true, role:result.role, permissions:result.permissions ?? [], mfaRequired:true, mfaVerified:result.mfa?.currentLevel==='aal2' })
    } catch (e:any) {
      setAdmin({ allowed:false, permissions:[], mfaRequired:true, mfaVerified:false })
      if (e?.code !== 'MFA_REQUIRED') setError(e?.message ?? 'Admin access denied.')
    }
  }

  useEffect(() => { void loadAdmin() }, [session])

  const signIn = async (event: React.FormEvent) => {
    event.preventDefault(); setError(''); setLoading(true)
    if (!supabase) { setError('Admin backend is not configured.'); setLoading(false); return }
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    setLoading(false)
    if (error) setError(error.message)
  }

  const verifyMfa = async () => {
    if (!supabase || !mfaFactorId || mfaCode.length < 6) return
    setError(''); setLoading(true)
    const challenge = await supabase.auth.mfa.challenge({ factorId:mfaFactorId })
    if (challenge.error) { setError(challenge.error.message); setLoading(false); return }
    const result = await supabase.auth.mfa.verify({ factorId:mfaFactorId, challengeId:challenge.data.id, code:mfaCode })
    setLoading(false)
    if (result.error) setError(result.error.message); else { setMfaCode(''); await loadAdmin() }
  }

  const signOut = async () => { await supabase?.auth.signOut() }

  if (!supabase) return <SetupScreen />
  if (!session || !user) return <LoginScreen email={email} password={password} setEmail={setEmail} setPassword={setPassword} error={error} loading={loading} onSubmit={signIn} />
  if (!admin?.allowed && mfaFactorId) return <MfaScreen user={user} code={mfaCode} setCode={setMfaCode} error={error} loading={loading} onVerify={verifyMfa} onSignOut={signOut} />
  if (!admin?.allowed) return <BlockedScreen user={user} onSignOut={signOut} />

  return <Dashboard section={section} setSection={setSection} onSignOut={signOut} role={admin.role?.name ?? 'Administrator'} />
}

function SetupScreen() { return <div className="center"><div className="card setup"><ShieldCheck size={42}/><h1>MELA Central Admin</h1><p>Configure <code>VITE_SUPABASE_URL</code>, <code>VITE_SUPABASE_PUBLISHABLE_KEY</code>, and <code>VITE_ADMIN_API_URL</code> in the separate deployment.</p></div></div> }
function LoginScreen(props: { email:string; password:string; setEmail:(v:string)=>void; setPassword:(v:string)=>void; error:string; loading:boolean; onSubmit:(e:React.FormEvent)=>void }) { return <div className="center"><form className="card login" onSubmit={props.onSubmit}><div className="brand"><ShieldCheck size={34}/><div><strong>MELA</strong><span>Central Admin</span></div></div><h1>Administrator sign in</h1><p className="muted">Separate administrative entrance. Consumer accounts cannot access this dashboard.</p><label>Email<input type="email" autoComplete="username" value={props.email} onChange={e=>props.setEmail(e.target.value)} required /></label><label>Password<input type="password" autoComplete="current-password" value={props.password} onChange={e=>props.setPassword(e.target.value)} required /></label>{props.error && <div className="error"><AlertTriangle size={16}/>{props.error}</div>}<button disabled={props.loading}>{props.loading?'Signing in…':'Sign in securely'}</button><small>MFA is required for authorized administrators before privileged access is granted.</small></form></div> }
function MfaScreen({ user, code, setCode, error, loading, onVerify, onSignOut }: { user:User; code:string; setCode:(v:string)=>void; error:string; loading:boolean; onVerify:()=>void; onSignOut:()=>void }) { return <div className="center"><div className="card login"><div className="brand"><ShieldCheck size={34}/><div><strong>MELA</strong><span>Central Admin</span></div></div><h1>Verify MFA</h1><p className="muted">Enter the current code from your registered authenticator for {user.email}.</p><input className="mfa" inputMode="numeric" autoComplete="one-time-code" maxLength={6} value={code} onChange={e=>setCode(e.target.value.replace(/\D/g,''))}/>{error&&<div className="error"><AlertTriangle size={16}/>{error}</div>}<button disabled={loading||code.length<6} onClick={onVerify}>{loading?'Verifying…':'Verify and continue'}</button><button className="secondary" onClick={onSignOut}>Cancel</button></div></div> }
function BlockedScreen({ user, onSignOut }: { user:User; onSignOut:()=>void }) { return <div className="center"><div className="card blocked"><LockKeyhole size={42}/><h1>Admin access required</h1><p>Your account <strong>{user.email}</strong> is not authorized for MELA Central Admin.</p><p className="muted">The dashboard fails closed. No consumer role is promoted automatically.</p><button onClick={onSignOut}>Sign out</button></div></div> }
function Dashboard({ section, setSection, onSignOut, role }: { section:Section; setSection:(s:Section)=>void; onSignOut:()=>void; role:string }) { return <div className="shell"><aside><div className="brand side"><ShieldCheck/><div><strong>MELA</strong><span>Central Admin</span></div></div><nav>{nav.map(item=>{const Icon=item.icon;return <button key={item.id} className={section===item.id?'active':''} onClick={()=>setSection(item.id)}><Icon size={18}/>{item.label}</button>})}</nav><div className="admin-role">{role}</div><button className="logout" onClick={onSignOut}><LogOut size={18}/>Sign out</button></aside><main><header><div><span className="eyebrow">CONTROL PLANE</span><h1>{nav.find(x=>x.id===section)?.label}</h1></div><div className="status"><span/>MFA-protected admin session</div></header>{section==='overview'&&<Overview/>}{section==='users'&&<Placeholder title="User Management" body="Search, verify, suspend and inspect users through audited backend actions."/>}{section==='access'&&<Placeholder title="Authorization & Access Control" body="Permission matrix, RLS coverage, access requests and session controls are the foundation layer."/>}{section==='audit'&&<Placeholder title="Audit Log" body="Every privileged mutation will be recorded with actor, action, target, before/after and timestamp."/>}{section==='settings'&&<Placeholder title="System Configuration" body="Feature flags, localization, career verticals and platform configuration will live here."/>}</main></div> }
function Overview() { const cards=useMemo(()=>[['Users','—'],['Open tickets','—'],['Pending disputes','—'],['Failed transactions','—']],[]); return <><div className="notice"><RefreshCw size={18}/><span>Authorization foundation is connected. Operational metrics will be enabled through audited admin actions next.</span></div><section className="grid">{cards.map(([label,value])=><div className="metric" key={label}><span>{label}</span><strong>{value}</strong><small>Awaiting operational adapter</small></div>)}</section><section className="panel"><h2>Security foundation</h2><div className="checks"><div><ShieldCheck/> Separate application</div><div><ShieldCheck/> Fail-closed authorization</div><div><ShieldCheck/> MFA required</div><div><ShieldCheck/> Audited privileged writes</div><div><ShieldCheck/> Shared MELA backend</div><div><ShieldCheck/> No service key in browser</div></div></section></> }
function Placeholder({ title, body }: {title:string; body:string}) { return <section className="panel"><h2>{title}</h2><p>{body}</p><div className="coming">Foundation-first implementation in progress.</div></section> }
createRoot(document.getElementById('root')!).render(<App />)
