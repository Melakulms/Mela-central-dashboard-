import { useEffect, useState } from 'react'
import type { SupabaseClient } from '@supabase/supabase-js'

type Entry = {
  id: number; title:string; country:string; degree_level:string
  cycle:string; research_state:string; admin_approved_at:string|null
  scholarship_url:string; evidence_checked_on:string; closes_on:string|null
}
export default function ScholarshipResearchReviewPanel({client}:{client:SupabaseClient}) {
  const [items,setItems]=useState<Entry[]>([])
  const [notes,setNotes]=useState<Record<number,string>>({})
  const [action,setAction]=useState<Record<number,'approve'|'withdraw'>>({})
  const [error,setError]=useState('')
  const [notice,setNotice]=useState('')
  const [busy,setBusy]=useState(false)
  const [loading,setLoading]=useState(true)
  const [revision,setRevision]=useState(0)
  useEffect(()=>{
    let active=true
    setLoading(true);setError('')
    void(async()=>{
      try {
        const {data:mfa,error:mfaErr}=await client.auth.mfa.getAuthenticatorAssuranceLevel()
        if(mfaErr)throw mfaErr
        if(mfa?.currentLevel!=='aal2')throw new Error('Authenticator MFA is required for scholarship review')
        const {data,error:loadError}=await client.from('mela_scholarship_program_research')
          .select('id,title,country,degree_level,cycle,research_state,admin_approved_at,scholarship_url,evidence_checked_on,closes_on')
          .order('id').limit(250)
        if(loadError)throw loadError
        if(active)setItems((data??[]) as Entry[])
      }catch(cause){if(active)setError(cause instanceof Error?cause.message:'Scholarship review queue unavailable')}
      finally{if(active)setLoading(false)}
    })()
    return()=>{active=false}
  },[client,revision])
  const update=async(item:Entry)=>{
    if(busy)return
    const note=(notes[item.id]??'').trim()
    const decision=action[item.id]??'approve'
    if(note.length<15||note.length>1000){setError('Explain the official source checks and reason in 15–1000 characters.');return}
    setBusy(true);setError('');setNotice('')
    try{
      const {data:mfa,error:mfaError}=await client.auth.mfa.getAuthenticatorAssuranceLevel()
      if(mfaError||mfa?.currentLevel!=='aal2')throw new Error('Administrator MFA session expired')
      const {error}=await client.rpc('mela_review_scholarship_program',{
        p_program_id:item.id,p_action:decision,p_reason:note
      })
      if(error)throw error
      setNotice('Scholarship research decision recorded with an internal audit record.')
      setNotes(old=>({...old,[item.id]:''}))
      setRevision(n=>n+1)
    }catch(cause){setError(cause instanceof Error?cause.message:'Could not complete reviewed change')}
    finally{setBusy(false)}
  }
  return <section className="panel" aria-label="Scholarship source verification">
    <div className="module-head"><div>
      <h2>Scholarship source review — staging</h2>
      <p>Independently validate current university rules, Ethiopian eligibility, fees, degree level and deadlines. Each decision is MFA-gated and audited.</p>
    </div><button className="refresh" onClick={()=>setRevision(n=>n+1)} disabled={busy}>Refresh</button></div>
    <p className="muted">Research status is not an admission or funding guarantee. Approval marks MELA administrator review, not an application submitted on a student's behalf. Production and payments remain unchanged.</p>
    {error&&<div className="error" role="alert">{error}</div>}
    {notice&&<p role="status">{notice}</p>}
    {loading?<p role="status">Loading programme verification queue…</p>:
      !items.length?<p>No programmes in the current review queue.</p>:
      items.map(item=><article key={item.id} className="detail-card">
        <h3>{item.title}</h3>
        <p>{item.country} · {item.degree_level} · {item.cycle}</p>
        <p>Research: {item.research_state} · {item.admin_approved_at?'MELA admin-reviewed':'Not MELA admin-reviewed'} · Source checked {item.evidence_checked_on}</p>
        <p>Recorded deadline: {item.closes_on||'Not confirmed'}</p>
        <a href={item.scholarship_url} target="_blank" rel="noopener noreferrer">Review original university scholarship page</a>
        <div><label htmlFor={'scholarship-decision-'+item.id}>Review action</label>
          <select id={'scholarship-decision-'+item.id} value={action[item.id]??'approve'} onChange={e=>setAction(old=>({...old,[item.id]:e.target.value as 'approve'|'withdraw'}))}>
            <option value="approve">Approve source review</option><option value="withdraw">Withdraw misleading or outdated research</option>
          </select>
        </div>
        <label htmlFor={'scholarship-note-'+item.id}>Review evidence or withdrawal explanation</label>
        <textarea id={'scholarship-note-'+item.id} maxLength={1000} placeholder="Document evidence checked directly at the official university source, eligibility and current deadlines." value={notes[item.id]??''} onChange={e=>setNotes(old=>({...old,[item.id]:e.target.value}))}/>
        <button disabled={busy||(notes[item.id]??'').trim().length<15} onClick={()=>void update(item)}>{busy?'Saving…':'Record reviewed decision'}</button>
      </article>)}
  </section>
}
