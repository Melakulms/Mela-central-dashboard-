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
    // Aggregate only counts; never load profile documents, meeting notes,
    // contact information or learner-submitted assignments to this panel.
    Promise.all([
      client.from('mentor_profiles').select('user_id, verified, active').limit(2000),
      client.from('mentorship_requests').select('id,status').limit(2000),
      client.from('mentorship_sessions').select('id,status').limit(2000),
    ]).then(([mentorsResult, requestsResult, sessionsResult]) => {
      if (mentorsResult.error) throw mentorsResult.error
      if (requestsResult.error) throw requestsResult.error
      if (sessionsResult.error) throw sessionsResult.error
      const mentors = mentorsResult.data ?? []
      const requests = requestsResult.data ?? []
      const sessions = sessionsResult.data ?? []
      const result: Snapshot = {
        mentorCount: mentors.length,
        activeVerified: mentors.filter((m) => m.verified && m.active).length,
        pendingVerification: mentors.filter((m) => !m.verified).length,
        requestCount: requests.length,
        pendingRequests: requests.filter((r) => r.status === 'pending').length,
        acceptedRequests: requests.filter((r) => r.status === 'accepted').length,
        sessionCount: sessions.length,
        scheduledSessions: sessions.filter((s) => s.status === 'scheduled').length,
        completedSessions: sessions.filter((s) => s.status === 'completed').length,
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
    <p className="muted">Counts are limited to the first 2,000 authorized records per type. They are not guaranteed platform-wide totals if that limit is reached.</p>
  </section>
}
