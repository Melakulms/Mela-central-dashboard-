import { useEffect, useState } from 'react'
import type { SupabaseClient } from '@supabase/supabase-js'

type Snapshot = {
  mentorCount: number
  activeVerified: number
  pendingVerification: number
  requestCount: number
  pendingRequests: number
  acceptedRequests: number
  sessionCount: number
  scheduledSessions: number
  completedSessions: number
}

export default function MentorshipOversightPanel({ client }: { client: SupabaseClient }) {
  const [snapshot, setSnapshot] = useState<Snapshot | null>(null)
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(true)
  const [revision, setRevision] = useState(0)

  useEffect(() => {
    let active = true
    setLoading(true); setError('')
    // Supabase returns COUNT without loading private student or mentor records.
    Promise.all([
      client.from('mentor_profiles').select('user_id',{count:'exact',head:true}),
      client.from('mentor_profiles').select('user_id',{count:'exact',head:true}).eq('verified',true).eq('active',true),
      client.from('mentor_profiles').select('user_id',{count:'exact',head:true}).eq('verified',false),
      client.from('mentorship_requests').select('id',{count:'exact',head:true}),
      client.from('mentorship_requests').select('id',{count:'exact',head:true}).eq('status','pending'),
      client.from('mentorship_requests').select('id',{count:'exact',head:true}).eq('status','accepted'),
      client.from('mentorship_sessions').select('id',{count:'exact',head:true}),
      client.from('mentorship_sessions').select('id',{count:'exact',head:true}).eq('status','scheduled'),
      client.from('mentorship_sessions').select('id',{count:'exact',head:true}).eq('status','completed'),
    ]).then((results) => {
      for (const result of results) if (result.error) throw result.error
      const values = results.map((result) => result.count ?? 0)
      const result: Snapshot = {
        mentorCount: values[0],
        activeVerified: values[1],
        pendingVerification: values[2],
        requestCount: values[3],
        pendingRequests: values[4],
        acceptedRequests: values[5],
        sessionCount: values[6],
        scheduledSessions: values[7],
        completedSessions: values[8],
      }
      if (active) setSnapshot(result)
    }).catch((cause) => {
      if (active) setError(cause instanceof Error ? cause.message : 'Mentorship totals are unavailable.')
    }).finally(() => { if (active) setLoading(false) })
    return () => { active = false }
  }, [client,revision])

  const rows = snapshot ? [
    ['Mentor applications with profiles',snapshot.mentorCount],
    ['Verified active mentors',snapshot.activeVerified],
    ['Mentors not yet verified',snapshot.pendingVerification],
    ['Mentorship requests',snapshot.requestCount],
    ['Pending requests',snapshot.pendingRequests],
    ['Accepted requests',snapshot.acceptedRequests],
    ['Sessions',snapshot.sessionCount],
    ['Scheduled sessions',snapshot.scheduledSessions],
    ['Completed sessions',snapshot.completedSessions],
  ] as const : []

  return <section className="panel" aria-label="Mentorship operational overview">
    <h2>Mentorship operational overview</h2>
    <p>This is a read-only, permission-controlled operational snapshot. No learner documents, messages, assignment responses or mentor credentials are exposed in this summary.</p>
    <button type="button" onClick={() => setRevision((v) => v + 1)} disabled={loading}>Refresh overview</button>
    {loading && <p role="status">Loading mentorship totals…</p>}
    {error && <div role="alert" className="error">{error}</div>}
    {snapshot && !error && <div className="grid">
      {rows.map(([label,value]) => <div className="metric" key={label}><span>{label}</span><strong>{value}</strong></div>)}
    </div>}
    <p className="muted">Counts use authorized database COUNT queries; no private records are loaded into this summary.</p>
  </section>
}
