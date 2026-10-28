import { useCallback, useEffect, useRef, useState } from 'react'
import type { SupabaseClient } from '@supabase/supabase-js'

type RecoveryRequest = {
  id: string
  mentor_id: string
  created_at: string
  eligible_after: string
  reason: string
  status: 'pending' | 'approved' | 'processing' | 'completed' | 'rejected'
  review_count: number
}

/** Staging-only security console; server RPCs re-validate admin + AAL2 on each call. */
export default function MentorMfaRecoveryPanel({ client }: { client: SupabaseClient }) {
  const [requests, setRequests] = useState<RecoveryRequest[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  const [evidenceReference, setEvidenceReference] = useState('')
  const [verifiedIdentity, setVerifiedIdentity] = useState(false)
  const [activeRequest, setActiveRequest] = useState('')
  const [busy, setBusy] = useState(false)
  const lock = useRef(false)

  const refresh = useCallback(async () => {
    setLoading(true); setError('')
    try {
      const { data, error: loadError } = await client.rpc('list_mentor_mfa_recovery_requests')
      if (loadError) throw loadError
      setRequests(Array.isArray(data) ? data as RecoveryRequest[] : [])
    } catch (cause) {
      setRequests([])
      setError(cause instanceof Error ? cause.message : 'Recovery queue unavailable.')
    } finally { setLoading(false) }
  }, [client])

  useEffect(() => {
    void refresh()
    const clear = () => { setRequests([]); setEvidenceReference(''); setVerifiedIdentity(false) }
    window.addEventListener('mela:session-boundary', clear)
    return () => window.removeEventListener('mela:session-boundary', clear)
  }, [refresh])

  const run = async (id: string, action: () => Promise<void>) => {
    if (lock.current) return
    lock.current = true; setBusy(true); setActiveRequest(id)
    setError(''); setNotice('')
    try {
      const { data: level, error: levelError } = await client.auth.mfa.getAuthenticatorAssuranceLevel()
      if (levelError) throw levelError
      if (level?.currentLevel !== 'aal2') throw new Error('Staff authenticator verification is required.')
      await action()
      setEvidenceReference(''); setVerifiedIdentity(false)
      await refresh()
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Recovery action could not be completed.')
    } finally { lock.current = false; setBusy(false); setActiveRequest('') }
  }

  const review = (r: RecoveryRequest, approve: boolean) => {
    if (approve && (!verifiedIdentity || evidenceReference.trim().length < 12)) {
      setError('Verify the applicant identity through the approved independent procedure first.')
      return
    }
    void run(r.id, async () => {
      const { error: rpcError } = await client.rpc('review_mentor_mfa_recovery', {
        p_request_id: r.id,
        p_evidence_reference: approve ? evidenceReference.trim() : null,
        p_approve: approve,
      })
      if (rpcError) throw rpcError
      setNotice(approve ? 'Your independent review was recorded.' : 'Request rejected.')
    })
  }
  const execute = (r: RecoveryRequest) => {
    if (!verifiedIdentity || evidenceReference.trim().length < 12) {
      setError('Verify the approved review history and evidence before execution.')
      return
    }
    if (new Date(r.eligible_after).getTime() > Date.now() || r.review_count < 2) {
      setError('The hold period or two independent approvals are not complete.')
      return
    }
    void run(r.id, async () => {
      const { data, error: fnError } = await client.functions.invoke('mentor-mfa-recovery-execute', {
        body: { request_id: r.id },
      })
      if (fnError) throw fnError
      if (!data || typeof data.message !== 'string' || !data.message.includes('Recovery completed')) {
        throw new Error(data?.message || 'MFA reset was not confirmed.')
      }
      setNotice('Reset completed. Existing sessions were revoked and the mentor must re-enroll MFA.')
    })
  }

  return <section className="panel" aria-label="Mentor authenticator recovery">
    <div className="module-head"><h2>Mentor MFA recovery — security review</h2>
      <button type="button" disabled={busy || loading} onClick={() => void refresh()}>Refresh</button>
    </div>
    <p>Reset requests require two separate MFA-verified reviewers, independent identity verification and a 24-hour hold. A password, email message or user-provided statement alone is insufficient evidence. Do not enter personal documents or OTPs here.</p>
    {error && <p role="alert">{error}</p>}
    {notice && <p role="status">{notice}</p>}
    {loading ? <p role="status">Checking recovery requests…</p> : requests.length === 0 ? <p>No recovery requests found.</p> : requests.map(r =>
      <article key={r.id} className="panel" style={{ marginTop: '1rem', padding: '1rem' }}>
        <h3>Recovery request {r.id.slice(0, 8)}</h3>
        <p>Mentor: <code>{r.mentor_id}</code></p>
        <p>Status: {r.status} · Reviews: {r.review_count}/2</p>
        <p>Reason: {r.reason} · Earliest execution: {new Date(r.eligible_after).toLocaleString()}</p>
        {(r.status === 'pending' || r.status === 'approved') && <>
          <label htmlFor={`recovery-evidence-${r.id}`}>Independent identity-verification case reference</label>
          <input id={`recovery-evidence-${r.id}`} disabled={busy}
            value={activeRequest === r.id ? evidenceReference : ''} onFocus={() => {
              setActiveRequest(r.id); setEvidenceReference(''); setVerifiedIdentity(false)
            }} onChange={e => setEvidenceReference(e.target.value.slice(0,128))}
            placeholder="Case reference, not a password or document" />
          {activeRequest === r.id && <label style={{display:'block'}}>
            <input type="checkbox" checked={verifiedIdentity} disabled={busy}
              onChange={e => setVerifiedIdentity(e.target.checked)} />
            I independently verified identity through the approved secure support process.
          </label>}
          <div style={{display:'flex',flexWrap:'wrap',gap:'.5rem',marginTop:'.75rem'}}>
            <button type="button" disabled={busy || activeRequest !== r.id || !verifiedIdentity || evidenceReference.trim().length<12}
              onClick={() => review(r,true)}>Record independent approval</button>
            <button type="button" disabled={busy || activeRequest !== r.id}
              onClick={() => review(r,false)}>Reject</button>
            {r.status === 'approved' && <button type="button"
              disabled={busy || activeRequest !== r.id || !verifiedIdentity || evidenceReference.trim().length<12 ||
                new Date(r.eligible_after).getTime()>Date.now() || r.review_count<2}
              onClick={() => execute(r)}>Execute approved reset</button>}
          </div>
        </>}
        {r.status === 'processing' && <p role="status">Processing or requiring manual security reconciliation. Do not repeat an unverified reset.</p>}
      </article>
    )}
  </section>
}
