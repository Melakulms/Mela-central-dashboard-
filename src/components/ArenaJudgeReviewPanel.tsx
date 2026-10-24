import { useEffect, useMemo, useState } from 'react'
import type { SupabaseClient } from '@supabase/supabase-js'

type Submission = {
  id: string
  round_id: string
  match_id: string
  user_id: string
  response: unknown
  submitted_at: string
  score: number | null
}
type RoundInfo = { id:string;prompt:string;max_points:number;state:string }

export default function ArenaJudgeReviewPanel({client}:{client:SupabaseClient}) {
  const [items,setItems]=useState<Submission[]>([])
  const [rounds,setRounds]=useState<Record<string,RoundInfo>>({})
  const [scores,setScores]=useState<Record<string,string>>({})
  const [notes,setNotes]=useState<Record<string,string>>({})
  const [loading,setLoading]=useState(true)
  const [busy,setBusy]=useState<string|null>(null)
  const [error,setError]=useState('')
  const [notice,setNotice]=useState('')
  const [refresh,setRefresh]=useState(0)

  useEffect(()=>{
    let active=true
    setLoading(true);setError('')
    void(async()=>{
      try {
        const {data:aal,error:aalError}=await client.auth.mfa.getAuthenticatorAssuranceLevel()
        if(aalError || aal?.currentLevel!=='aal2')throw new Error('Arena grading requires the verified administrator MFA session.')
        const {data,error:loadError}=await client.from('arena_round_submissions')
          .select('id,round_id,match_id,user_id,response,submitted_at,score')
          .is('score',null).order('submitted_at',{ascending:true}).limit(50)
        if(loadError)throw loadError
        const unreviewed=(data??[]) as Submission[]
        const ids=[...new Set(unreviewed.map(x=>x.round_id))]
        let lookup:Record<string,RoundInfo>={}
        if(ids.length>0){
          const {data:roundData,error:roundError}=await client.from('arena_rounds')
            .select('id,prompt,max_points,state').in('id',ids)
          if(roundError)throw roundError
          lookup=Object.fromEntries(((roundData??[]) as RoundInfo[]).map(x=>[x.id,x]))
        }
        if(active){setItems(unreviewed);setRounds(lookup)}
      }catch(cause){if(active)setError(cause instanceof Error?cause.message:'Arena review queue could not be retrieved')}
      finally{if(active)setLoading(false)}
    })()
    return()=>{active=false}
  },[client,refresh])

  const reviewable=useMemo(()=>items.filter(item=>rounds[item.round_id]?.state==='closed'),[items,rounds])

  async function grade(item:Submission){
    if(busy)return
    const round=rounds[item.round_id]
    const raw=(scores[item.id]??'').trim()
    const score=Number(raw)
    const note=(notes[item.id]??'').trim()
    if(!round||round.state!=='closed'){setError('The round must be closed before grading.');return}
    if(!raw||!Number.isFinite(score)||score<0||score>round.max_points){setError('Enter a score from zero to the round maximum.');return}
    if(note.length<8||note.length>1000){setError('Explain the grade in 8–1000 characters.');return}
    setBusy(item.id);setError('');setNotice('')
    try{
      const {data:aal,error:aalError}=await client.auth.mfa.getAuthenticatorAssuranceLevel()
      if(aalError||aal?.currentLevel!=='aal2')throw new Error('Administrator MFA session is no longer verified.')
      const {error:reviewError}=await client.rpc('staging_arena_review_submission_v1',{
        p_submission_id:item.id,p_score:score,p_feedback:note,
      })
      if(reviewError)throw reviewError
      setNotice('Grade saved. Match results finalize only after all submissions receive authorized reviews.')
      setScores(old=>({...old,[item.id]:''}))
      setNotes(old=>({...old,[item.id]:''}))
      setRefresh(x=>x+1)
    }catch(cause){setError(cause instanceof Error?cause.message:'Arena grade could not be recorded')}
    finally{setBusy(null)}
  }
  return <section className="panel" aria-label="Arena independent grading">
    <div className="module-head"><div>
      <h2>Arena written-answer review · STAGING</h2>
      <p>Independent MFA-authenticated judging. Only closed rounds can be graded; match participants cannot judge their own answers.</p>
    </div><button className="refresh" disabled={busy!==null} onClick={()=>setRefresh(n=>n+1)}>Refresh</button></div>
    <p className="muted">No coins, cash awards, or rated outcomes are enabled for this demo. All answers remain pending until reviewed.</p>
    {error&&<div className="error" role="alert">{error}</div>}
    {notice&&<p role="status">{notice}</p>}
    {loading?<p role="status">Loading Arena review queue…</p>:items.length===0?
      <p>No submitted written answers are awaiting review.</p>:<>
      <p>{reviewable.length} closed-round submissions ready for grading. {items.length-reviewable.length} still have active or inaccessible rounds.</p>
      {reviewable.map(item=>{
        const round=rounds[item.round_id]
        return <article className="detail-card" key={item.id}>
          <h3>Match {item.match_id.slice(0,8)} · Round {item.round_id.slice(0,8)}</h3>
          <p><strong>Prompt:</strong> {round.prompt}</p>
          <p><strong>Submission:</strong> {JSON.stringify(item.response)?.slice(0,1800)??'(empty)'}</p>
          <p className="muted">Submitted {new Date(item.submitted_at).toLocaleString()} · Maximum {round.max_points} points</p>
          <label htmlFor={'arena-score-'+item.id}>Score (0–{round.max_points})</label>
          <input id={'arena-score-'+item.id} type="number" min={0} max={round.max_points} step="1"
            value={scores[item.id]??''} onChange={e=>setScores(old=>({...old,[item.id]:e.target.value}))}/>
          <label htmlFor={'arena-note-'+item.id}>Reason for this score</label>
          <textarea id={'arena-note-'+item.id} maxLength={1000} value={notes[item.id]??''}
            placeholder="Explain assessment against the visible prompt and the submitted answer"
            onChange={e=>setNotes(old=>({...old,[item.id]:e.target.value}))}/>
          <button disabled={busy!==null||(notes[item.id]??'').trim().length<8}
            onClick={()=>void grade(item)}>{busy===item.id?'Saving grade…':'Record independent grade'}</button>
        </article>
      })}
    </>}
  </section>
}
