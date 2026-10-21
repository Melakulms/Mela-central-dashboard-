import { useRef, useState } from 'react'
import type { SupabaseClient } from '@supabase/supabase-js'
import { isScholarshipStagingUrl } from '../lib/scholarship-staging'

type Student = { id: string; full_name: string | null; email: string | null; account_status: string | null; education_stage_key: string | null }
type Product = { product_key: string; product_name: string; billing_period: string; product_type: string }
type Grant = { id: string; product_key: string; status: string; starts_at: string; ends_at: string | null; source_reference: string; created_at: string }
type Audit = { id: number; grant_id: string; actor: string; action: string; product_key: string; reason: string; created_at: string }
type Overview = { students: Student[]; products: Product[]; grants: Grant[]; audit: Audit[] }
const EMPTY: Overview = { students: [], products: [], grants: [], audit: [] }

function errorText(cause: unknown): string {
  return cause instanceof Error ? cause.message : 'The action could not be completed. Try again.'
}
function defaultEndDate(): string {
  const date = new Date()
  date.setDate(date.getDate() + 30)
  return date.getFullYear() + '-' + String(date.getMonth() + 1).padStart(2, '0') + '-' + String(date.getDate()).padStart(2, '0')
}
function activeGrant(row: Grant): boolean {
  return row.status === 'active' && (!row.ends_at || Date.parse(row.ends_at) > Date.now())
}

export default function ScholarshipAccessPanel({ client }: { client: SupabaseClient }) {
  const [query, setQuery] = useState('')
  const [students, setStudents] = useState<Student[]>([])
  const [products, setProducts] = useState<Product[]>([])
  const [student, setStudent] = useState<Student | null>(null)
  const [grants, setGrants] = useState<Grant[]>([])
  const [audit, setAudit] = useState<Audit[]>([])
  const [product, setProduct] = useState('')
  const [reason, setReason] = useState('')
  const [ends, setEnds] = useState(defaultEndDate)
  const [revokeTarget, setRevokeTarget] = useState<Grant | null>(null)
  const [revokeReason, setRevokeReason] = useState('')
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const [busy, setBusy] = useState(false)
  const inFlight = useRef(false)
  const staging = isScholarshipStagingUrl(import.meta.env.VITE_SUPABASE_URL)

  const fetchOverview = async (search: string, id: string | null): Promise<Overview> => {
    const { data, error } = await client.rpc('admin_learning_grant_query_v1', {
      p_search: search,
      p_learner: id,
    })
    if (error) throw error
    return data && typeof data === 'object' ? data as Overview : EMPTY
  }
  const run = async (fn: () => Promise<void>) => {
    if (inFlight.current) return
    inFlight.current = true
    setBusy(true); setError(''); setMessage('')
    try { await fn() } catch (cause) { setError(errorText(cause)) }
    finally { inFlight.current = false; setBusy(false) }
  }
  const searchStudents = () => void run(async () => {
    if (query.trim().length < 2) throw new Error('Enter at least two letters of a student name or email.')
    const result = await fetchOverview(query.trim(), null)
    setStudents(result.students || [])
    setProducts(result.products || [])
    setStudent(null); setGrants([]); setAudit([]); setRevokeTarget(null)
  })
  const selectStudent = (s: Student) => void run(async () => {
    const result = await fetchOverview('', s.id)
    setStudent(s); setStudents([])
    setProducts(result.products || [])
    setProduct(current => (result.products || []).some(p => p.product_key === current) ? current : (result.products || [])[0]?.product_key ?? '')
    setGrants(result.grants || []); setAudit(result.audit || []); setRevokeTarget(null)
  })
  const refresh = async (selected: Student) => {
    const data = await fetchOverview('', selected.id)
    setGrants(data.grants || []); setAudit(data.audit || [])
    setProducts(data.products || [])
  }
  const grant = (event: React.FormEvent) => {
    event.preventDefault()
    void run(async () => {
      if (!student || !product || !staging) throw new Error('A staging student and eligible product are required.')
      const cleaned = reason.trim()
      if (cleaned.length < 10 || cleaned.length > 500) throw new Error('Provide a reason between 10 and 500 characters.')
      if (student.account_status !== 'active') throw new Error('This learner must have active account access before a scholarship can be granted.')
      const endTime = ends ? new Date(ends + 'T23:59:59').toISOString() : null
      if (endTime && Date.parse(endTime) <= Date.now()) throw new Error('The end date must be in the future.')
      const { data, error: failure } = await client.rpc('admin_learning_access_v1', {
        p_action: 'admin_grant',
        p_data: { learner_user_id: student.id, product_key: product, reason: cleaned, ends_at: endTime },
      })
      if (failure) throw failure
      await refresh(student)
      setReason('')
      setMessage(data?.existing ? 'Existing scholarship returned; no duplicate was created. The request was audited.' : 'Student scholarship granted and audited.')
    })
  }
  const revoke = () => void run(async () => {
    if (!staging || !student || !revokeTarget) throw new Error('Select a grant to revoke.')
    const cleaned = revokeReason.trim()
    if (cleaned.length < 10 || cleaned.length > 500) throw new Error('Provide a revocation reason between 10 and 500 characters.')
    const { error: failure } = await client.rpc('admin_learning_access_v1', {
      p_action: 'admin_revoke',
      p_data: { learner_user_id: student.id, product_key: revokeTarget.product_key, reason: cleaned },
    })
    if (failure) throw failure
    await refresh(student)
    setRevokeTarget(null); setRevokeReason('')
    setMessage('Access revoked. The entitlement and permanent audit record were preserved.')
  })

  if (!staging) {
    return <section className="panel"><h2>Scholarships unavailable</h2><p>This administrator tool is only allowed when connected to MELA staging. No request has been sent.</p></section>
  }
  return <section className="panel scholarship-panel" aria-label="Scholarship and Free Access">
    <div className="module-head"><div><h2>Scholarship &amp; Free Access</h2><p>Staging only. Grant selected learning products to individual students without taking payment. Course enrollment is never changed here.</p></div><span className="total-badge">STAGING</span></div>
    <p className="notice">Only active payment reviewers with a verified MFA session may view or change grants. Every action, including a repeated request, is audited. Payment collection remains off.</p>
    {error && <div className="error" role="alert">{error}</div>}
    {message && <p role="status" className="scholarship-success">{message}</p>}
    <form className="scholarship-search" onSubmit={e => { e.preventDefault(); searchStudents() }}>
      <label htmlFor="scholarship-search">Find a student by name or email</label>
      <div className="scholarship-search-row">
        <input id="scholarship-search" autoComplete="off" value={query} maxLength={120} onChange={e => setQuery(e.target.value)} placeholder="Enter at least 2 letters" disabled={busy}/>
        <button type="submit" disabled={busy || query.trim().length < 2}>{busy ? 'Working…' : 'Search students'}</button>
      </div>
    </form>
    {!!students.length && <div className="scholarship-candidates" aria-label="Student search results">
      {students.map(s => <button key={s.id} type="button" disabled={busy} onClick={() => selectStudent(s)}>
        <strong>{s.full_name || 'Unnamed student'}</strong><span>{s.email || s.id} · {s.account_status ?? 'unknown status'}</span>
      </button>)}
    </div>}
    {student && <>
      <section className="scholarship-card">
        <div className="module-head"><div><h3>{student.full_name || 'Student account'}</h3><p>{student.email || student.id} · {student.account_status}</p></div><button type="button" disabled={busy} onClick={() => void run(() => refresh(student))}>Refresh grants</button></div>
        <form onSubmit={grant} className="scholarship-form">
          <h3>Grant product access</h3>
          <label htmlFor="scholarship-product">Eligible learning product</label>
          <select id="scholarship-product" value={product} onChange={e => setProduct(e.target.value)} disabled={busy} required>
            {!product && <option value="">Select a product</option>}
            {products.map(p => <option value={p.product_key} key={p.product_key}>{p.product_name}</option>)}
          </select>
          <label htmlFor="scholarship-reason">Written reason (10–500 characters)</label>
          <textarea id="scholarship-reason" required minLength={10} maxLength={500} value={reason} disabled={busy} onChange={e => setReason(e.target.value)} placeholder="Explain the scholarship or partner sponsorship"/>
          <label htmlFor="scholarship-end">End date (optional; 30 days suggested)</label>
          <input id="scholarship-end" type="date" value={ends} disabled={busy} onChange={e => setEnds(e.target.value)}/>
          <p className="muted">Clear the date for an open-ended grant. A duplicate request returns the existing grant and records another audit event.</p>
          <button type="submit" disabled={busy || !product || reason.trim().length < 10 || student.account_status !== 'active'}>Grant free product access</button>
        </form>
      </section>
      <section className="scholarship-card">
        <h3>Existing scholarship grants</h3>
        {!grants.length && <p>No administrator grants for this student.</p>}
        <div className="scholarship-history">{grants.map(g => <article key={g.id} className="scholarship-history-row">
          <div><strong>{products.find(p => p.product_key === g.product_key)?.product_name ?? g.product_key}</strong>
            <p>Status: {g.status}{g.status === 'active' && !activeGrant(g) ? ' (expired)' : ''} · Ends: {g.ends_at ? new Date(g.ends_at).toLocaleDateString() : 'No end date'}</p>
            <small>Grant: {g.source_reference}</small></div>
          {activeGrant(g) && <button type="button" disabled={busy} onClick={() => {setRevokeTarget(g);setRevokeReason('')}}>Revoke</button>}
        </article>)}</div>
        {revokeTarget && <div className="scholarship-revoke" role="group" aria-label="Confirm scholarship revocation">
          <h4>Confirm access revocation</h4>
          <p>This permanently ends the selected grant, preserves its row and records your reason.</p>
          <label htmlFor="scholarship-revoke-reason">Reason (10–500 characters)</label>
          <textarea id="scholarship-revoke-reason" value={revokeReason} disabled={busy} minLength={10} maxLength={500} onChange={e => setRevokeReason(e.target.value)}/>
          <div className="scholarship-search-row"><button type="button" disabled={busy} onClick={() => setRevokeTarget(null)}>Keep access</button><button className="danger-btn" type="button" disabled={busy || revokeReason.trim().length < 10} onClick={revoke}>Confirm revoke</button></div>
        </div>}
      </section>
      <section className="scholarship-card"><h3>Grant audit history</h3>
        {!audit.length && <p>No audit records for this student.</p>}
        <div className="scholarship-history">{audit.map(a => <article className="scholarship-history-row" key={a.id}><div><strong>{a.action} · {a.product_key}</strong><p>{a.reason}</p><small>{new Date(a.created_at).toLocaleString()} · Reviewer {a.actor}</small></div></article>)}</div>
      </section>
    </>}
  </section>
}
