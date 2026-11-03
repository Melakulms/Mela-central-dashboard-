import { useEffect, useRef, useState, type FormEvent } from 'react'
import type { SupabaseClient } from '@supabase/supabase-js'

type Checkpoint = 'requester_identity' | 'guardian_authority' | 'scope_and_third_parties' |
  'retention_and_legal_basis' | 'safeguarding_review' | 'fulfillment_plan'
type Finding = 'needs_follow_up' | 'reviewed_no_issue_identified'
type RecordedCheckpoint = {
  id: string
  checkpoint: Checkpoint
  finding: Finding
  recorded_at: string
  reviewer_id: string
}

const CHECKPOINTS: {value:Checkpoint;label:string;purpose:string}[] = [
  {value:'requester_identity',label:'Requester identity',
    purpose:'Assess whether the requester controls the account; do not save identity documents here'},
  {value:'guardian_authority',label:'Guardian authority (when relevant)',
    purpose:'Assess legal authority for a minor; a supplied guardian contact is not verification'},
  {value:'scope_and_third_parties',label:'Scope and third-party rights',
    purpose:'Identify affected records and any unrelated personal information that must not be disclosed'},
  {value:'retention_and_legal_basis',label:'Retention obligations and lawful basis',
    purpose:'Identify records that cannot be changed or erased without a legal review'},
  {value:'safeguarding_review',label:'Child protection and incident considerations',
    purpose:'Check whether safeguarding evidence or an ongoing incident requires restricted handling'},
  {value:'fulfillment_plan',label:'Fulfillment and secure delivery plan',
    purpose:'Assess the next authorized action; this does not execute it or approve fulfillment'},
]
const FINDING_LABELS: Record<Finding,string> = {
  needs_follow_up:'Needs additional verification or action',
  reviewed_no_issue_identified:'Reviewed — no issue identified at this checkpoint',
}

/**
 * Append-only observations made by the assigned AAL2 super administrator.
 * These are staff attestations, not proof of actual identity verification,
 * legal approval or fulfillment. Never collect sensitive evidence in this table.
 */
export default function PrivacyReviewCheckpointPanel({client,requestId,assignedReviewerId}:{
  client: SupabaseClient
  requestId: string
  assignedReviewerId: string | null
}) {
  const [entries,setEntries] = useState<RecordedCheckpoint[]>([])
  const [currentUserId,setCurrentUserId] = useState<string | null>(null)
  const [loading,setLoading] = useState(true)
  const [refresh,setRefresh] = useState(0)
  const [category,setCategory] = useState<Checkpoint>('requester_identity')
  const [finding,setFinding] = useState<Finding>('needs_follow_up')
  const [confirmed,setConfirmed] = useState(false)
  const [busy,setBusy] = useState(false)
  const [error,setError] = useState('')
  const [notice,setNotice] = useState('')
  const lock = useRef(false)

  useEffect(() => {
    let active=true
    setLoading(true)
    setError('')
    setEntries([])
    void (async () => {
      try {
        const {data: assurance,error:assuranceError} = await client.auth.mfa.getAuthenticatorAssuranceLevel()
        if(assuranceError) throw assuranceError
        if(assurance?.currentLevel !== 'aal2') throw new Error('Authenticator verification is required.')
        const {data: auth,error:authError} = await client.auth.getUser()
        if(authError || !auth.user) throw new Error('Sign in again to review privacy checkpoints.')
        const {data, error: readError} = await client.from('privacy_review_checkpoints')
          .select('id,checkpoint,finding,recorded_at,reviewer_id')
          .eq('request_id',requestId)
          .order('recorded_at',{ascending:false}).limit(60)
        if(readError) throw readError
        if(active){setCurrentUserId(auth.user.id);setEntries((data??[]) as RecordedCheckpoint[])}
      } catch(cause){
        if(active){setCurrentUserId(null);setError(cause instanceof Error?cause.message:'Could not load restricted checkpoints.')}
      } finally {if(active) setLoading(false)}
    })()
    return () => {active=false}
  },[client,requestId,refresh])

  const canRecord = !loading && !error && currentUserId !== null &&
    currentUserId === assignedReviewerId
  const latest = CHECKPOINTS.map(item=>({
    ...item,entry:entries.find(entry=>entry.checkpoint===item.value),
  }))
  const observed = latest.filter(item=>item.entry).length
  const attention = latest.filter(item=>item.entry?.finding==='needs_follow_up').length

  async function submit(event: FormEvent<HTMLFormElement>){
    event.preventDefault()
    if(lock.current||busy||!canRecord||!confirmed) return
    lock.current=true
    setBusy(true)
    setError('')
    setNotice('')
    try{
      const {data: assurance,error: assuranceError} = await client.auth.mfa.getAuthenticatorAssuranceLevel()
      if(assuranceError) throw assuranceError
      if(assurance?.currentLevel!=='aal2') throw new Error('Authenticator verification expired.')
      const {data: auth,error:authError} = await client.auth.getUser()
      if(authError || !auth.user || auth.user.id!==assignedReviewerId)
        throw new Error('Only the assigned reviewer may record this checkpoint.')
      const {data,error:writeError} = await client.from('privacy_review_checkpoints')
        .insert({request_id:requestId,reviewer_id:auth.user.id,checkpoint:category,finding})
        .select('id').maybeSingle()
      if(writeError) throw writeError
      if(!data) throw new Error('No checkpoint was recorded. Refresh the case and retry.')
      setConfirmed(false)
      setNotice('Checkpoint observation recorded with an audit entry. The request is still open; nothing was fulfilled or approved.')
      setRefresh(value=>value+1)
    }catch(cause){
      setError(cause instanceof Error?cause.message:'Could not record checkpoint.')
    }finally{lock.current=false;setBusy(false)}
  }

  return <section aria-label="Internal privacy review checkpoints" className="detail-card">
    <h4>Pre-decision review checkpoints (restricted)</h4>
    <p className="muted">Append-only staff observations. These are not independent evidence, verified identity documents, legal approval, or permission to complete the request. The audit logs the category and finding, not private documents.</p>
    {notice && <p role="status">{notice}</p>}
    {error && <p role="alert" className="error">{error}</p>}
    {loading ? <p role="status">Loading restricted checkpoints…</p> : <>
      <p role="status">{observed} of {CHECKPOINTS.length} categories have recorded observations; {attention} currently need follow-up. An entry does not mean the related legal requirement is satisfied.</p>
      <ul>{latest.map(item=><li key={item.value}>
        <strong>{item.label}</strong> — {item.entry
          ? FINDING_LABELS[item.entry.finding]
          : 'Not assessed'}
        {item.entry && <span className="muted"> (recorded {new Date(item.entry.recorded_at).toLocaleString()})</span>}
      </li>)}</ul>
      <p className="muted">This view shows the latest observation in each category; {entries.length} recorded entries loaded. Older observations remain append-only. Do not upload documents or write identifying details into checklist fields.</p>
      {!canRecord && !error && <p role="status">Only the assigned reviewer can record checkpoints. Other authorized super administrators can inspect the checklist.</p>}
      {canRecord && <form onSubmit={event=>void submit(event)}>
        <label htmlFor="privacy-checkpoint-category">Review checkpoint
          <select id="privacy-checkpoint-category" value={category} onChange={e=>{setCategory(e.target.value as Checkpoint);setConfirmed(false)}} disabled={busy}>
            {CHECKPOINTS.map(x=><option key={x.value} value={x.value}>{x.label}</option>)}
          </select>
        </label>
        <p className="muted">{CHECKPOINTS.find(x=>x.value===category)?.purpose}</p>
        <label htmlFor="privacy-checkpoint-finding">Recorded observation
          <select id="privacy-checkpoint-finding" value={finding} onChange={e=>{setFinding(e.target.value as Finding);setConfirmed(false)}} disabled={busy}>
            <option value="needs_follow_up">{FINDING_LABELS.needs_follow_up}</option>
            <option value="reviewed_no_issue_identified">{FINDING_LABELS.reviewed_no_issue_identified}</option>
          </select>
        </label>
        <label><input type="checkbox" checked={confirmed} onChange={e=>setConfirmed(e.target.checked)} disabled={busy} />
          {' '}I personally assessed this checkpoint. I understand this creates an audited observation, does not verify identity automatically, and does not finish or approve the request.
        </label>
        <button type="submit" disabled={busy||!confirmed}>{busy?'Recording…':'Record checkpoint (audited)'}</button>
      </form>}
    </>}
    <button type="button" disabled={busy||loading} onClick={()=>setRefresh(v=>v+1)}>Refresh checkpoints</button>
  </section>
}
