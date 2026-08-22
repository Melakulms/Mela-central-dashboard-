import React, { useEffect, useMemo, useState } from 'react'
import { createRoot } from 'react-dom/client'
import { createClient, type Session, type User } from '@supabase/supabase-js'
import { ShieldCheck, LayoutDashboard, Users, LockKeyhole, FileClock, Settings, LogOut, AlertTriangle, RefreshCw } from 'lucide-react'
import './styles.css'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL as string | undefined
const supabaseKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string | undefined
const supabase = supabaseUrl && supabaseKey ? createClient(supabaseUrl, supabaseKey) : null

const nav = [
  { id: 'overview', label: 'Overview', icon: LayoutDashboard },
  { id: 'users', label: 'Users', icon: Users },
  { id: 'access', label: 'Authorization', icon: LockKeyhole },
  { id: 'audit', label: 'Audit Log', icon: FileClock },
  { id: 'settings', label: 'System', icon: Settings },
] as const

type Section = typeof nav[number]['id']

type AdminState = { allowed: boolean; role?: string; permissions: string[]; mfaRequired: boolean; mfaVerified: boolean }

function App() {
  const [session, setSession] = useState<Session | null>(null)
  const [user, setUser] = useState<User | null>(null)
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)
  const [section, setSection] = useState<Section>('overview')
  const [admin, setAdmin] = useState<AdminState | null>(null)

  useEffect(() => {
    if (!supabase) return
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session)
      setUser(data.session?.user ?? null)
    })
    const { data: listener } = supabase.auth.onAuthStateChange((_event, next) => {
      setSession(next)
      setUser(next?.user ?? null)
    })
    return () => listener.subscription.unsubscribe()
  }, [])

  useEffect(() => {
    if (!session || !supabase) { setAdmin(null); return }
    // Authorization is deliberately fail-closed. The backend must supply this state.
    setAdmin({ allowed: false, permissions: [], mfaRequired: true, mfaVerified: false })
  }, [session])

  const signIn = async (event: React.FormEvent) => {
    event.preventDefault()
    setError('')
    if (!supabase) { setError('Admin backend is not configured.'); return }
    setLoading(true)
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    setLoading(false)
    if (error) setError(error.message)
  }

  const signOut = async () => { await supabase?.auth.signOut() }

  if (!supabase) return <SetupScreen />
  if (!session || !user) return <LoginScreen email={email} password={password} setEmail={setEmail} setPassword={setPassword} error={error} loading={loading} onSubmit={signIn} />
  if (!admin?.allowed) return <BlockedScreen user={user} onSignOut={signOut} />

  return <Dashboard section={section} setSection={setSection} onSignOut={signOut} />
}

function SetupScreen() {
  return <div className="center"><div className="card setup"><ShieldCheck size={42}/><h1>MELA Central Admin</h1><p>Supabase configuration is missing. Add <code>VITE_SUPABASE_URL</code> and <code>VITE_SUPABASE_PUBLISHABLE_KEY</code> to the separate admin deployment.</p></div></div>
}

function LoginScreen(props: { email:string; password:string; setEmail:(v:string)=>void; setPassword:(v:string)=>void; error:string; loading:boolean; onSubmit:(e:React.FormEvent)=>void }) {
  return <div className="center"><form className="card login" onSubmit={props.onSubmit}><div className="brand"><ShieldCheck size={34}/><div><strong>MELA</strong><span>Central Admin</span></div></div><h1>Administrator sign in</h1><p className="muted">This is a separate administrative entrance. Consumer accounts cannot access it.</p><label>Email<input type="email" autoComplete="username" value={props.email} onChange={e=>props.setEmail(e.target.value)} required /></label><label>Password<input type="password" autoComplete="current-password" value={props.password} onChange={e=>props.setPassword(e.target.value)} required /></label>{props.error && <div className="error"><AlertTriangle size={16}/>{props.error}</div>}<button disabled={props.loading}>{props.loading ? 'Signing in…' : 'Sign in securely'}</button><small>MFA is required for authorized administrators before privileged access is granted.</small></form></div>
}

function BlockedScreen({ user, onSignOut }: { user:User; onSignOut:()=>void }) {
  return <div className="center"><div className="card blocked"><LockKeyhole size={42}/><h1>Admin access required</h1><p>Your authenticated account <strong>{user.email}</strong> is not currently authorized for the MELA Central Admin dashboard, or MFA has not been verified.</p><p className="muted">The dashboard fails closed. No consumer role is promoted automatically.</p><button onClick={onSignOut}>Sign out</button></div></div>
}

function Dashboard({ section, setSection, onSignOut }: { section:Section; setSection:(s:Section)=>void; onSignOut:()=>void }) {
  return <div className="shell"><aside><div className="brand side"><ShieldCheck/><div><strong>MELA</strong><span>Central Admin</span></div></div><nav>{nav.map(item=>{const Icon=item.icon;return <button key={item.id} className={section===item.id?'active':''} onClick={()=>setSection(item.id)}><Icon size={18}/>{item.label}</button>})}</nav><button className="logout" onClick={onSignOut}><LogOut size={18}/>Sign out</button></aside><main><header><div><span className="eyebrow">CONTROL PLANE</span><h1>{nav.find(x=>x.id===section)?.label}</h1></div><div className="status"><span/>Admin session protected</div></header>{section==='overview' && <Overview/>}{section==='users' && <Placeholder title="User Management" body="Search, verify, suspend and inspect users through audited backend actions."/>}{section==='access' && <Placeholder title="Authorization & Access Control" body="Permission matrix, RLS coverage, access requests and session controls are the foundation layer."/>}{section==='audit' && <Placeholder title="Audit Log" body="Every privileged mutation will be recorded with actor, action, target, before/after and timestamp."/>}{section==='settings' && <Placeholder title="System Configuration" body="Feature flags, localization, career verticals and platform configuration will live here."/>}</main></div>
}

function Overview() {
  const cards = useMemo(()=>[['Users','—'],['Open tickets','—'],['Pending disputes','—'],['Failed transactions','—']],[])
  return <><div className="notice"><RefreshCw size={18}/><span>Live backend metrics will appear after the admin authorization service is connected.</span></div><section className="grid">{cards.map(([label,value])=><div className="metric" key={label}><span>{label}</span><strong>{value}</strong><small>Awaiting authorized admin API</small></div>)}</section><section className="panel"><h2>Security foundation</h2><div className="checks"><div><ShieldCheck/> Separate application</div><div><ShieldCheck/> Fail-closed authorization</div><div><ShieldCheck/> MFA required</div><div><ShieldCheck/> Audited privileged writes</div><div><ShieldCheck/> Shared MELA backend</div><div><ShieldCheck/> No service key in browser</div></div></section></>
}

function Placeholder({ title, body }: {title:string; body:string}) { return <section className="panel"><h2>{title}</h2><p>{body}</p><div className="coming">Foundation-first implementation in progress.</div></section> }

createRoot(document.getElementById('root')!).render(<App />)
