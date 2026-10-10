import { useEffect, useRef, useState } from 'react'
import type { SupabaseClient } from '@supabase/supabase-js'
import { getAIAgents, getAIApprovals, getAIRuns, reviewAIApproval, setAgentEnabled, type Agent, type Approval, type AIRun, type AIPage } from './aiWorkforce'
const emptyPage={data:[],total:0}
function Pagination({name,page,total,disabled,onPage}:{name:string;page:number;total:number;disabled:boolean;onPage:(page:number)=>void}) {
 return <div className="toolbar" aria-label={`${name} pagination`}><button disabled={disabled||page===0} onClick={()=>onPage(page-1)}>Previous {name}</button><span>{total===0?'0 records':`${page*25+1}–${Math.min((page+1)*25,total)} of ${total}`}</span><button disabled={disabled||(page+1)*25>=total} onClick={()=>onPage(page+1)}>Next {name}</button></div>
}
export default function AIWorkforcePanel({client}:{client:SupabaseClient}) {
 const [agents,setAgents]=useState<Agent[]>([]),[approvals,setApprovals]=useState<AIPage<Approval>>(emptyPage),[runs,setRuns]=useState<AIPage<AIRun>>(emptyPage)
 const [loading,setLoading]=useState(true),[ready,setReady]=useState(false),[error,setError]=useState(''),[success,setSuccess]=useState(''),[busy,setBusy]=useState(false),[revision,setRevision]=useState(0)
 const [approvalPage,setApprovalPage]=useState(0),[runPage,setRunPage]=useState(0),[approvalStatus,setApprovalStatus]=useState('pending'),[runStatus,setRunStatus]=useState('')
 const [selected,setSelected]=useState<Approval|null>(null),[note,setNote]=useState(''),[runDetail,setRunDetail]=useState<AIRun|null>(null)
 const [message,setMessage]=useState(''),[answer,setAnswer]=useState('')
 const actionLock=useRef(false)
 useEffect(()=>{
  let active=true;setLoading(true);setError('');setReady(false)
  Promise.all([getAIAgents(client),getAIApprovals(client,approvalPage*25,approvalStatus),getAIRuns(client,runPage*25,runStatus)])
   .then(([a,p,r])=>{if(active){setAgents(a);setApprovals(p);setRuns(r);setReady(true)}})
   .catch(cause=>{if(active)setError(cause instanceof Error?cause.message:'Unable to load AI workforce. Please retry.')})
   .finally(()=>{if(active)setLoading(false)})
  return ()=>{active=false}
 },[client,approvalPage,runPage,approvalStatus,runStatus,revision])
 const run=async(action:()=>Promise<void>)=>{
  if(actionLock.current)return;actionLock.current=true;setBusy(true);setError('');setSuccess('')
  try{await action()}catch(cause){setError(cause instanceof Error?cause.message:'Unable to save this change. Please retry.')}
  finally{actionLock.current=false;setBusy(false)}
 }
 const execute=()=>run(async()=>{
  const text=message.trim();if(!text||text.length>6000)return
  const {data,error:invokeError}=await client.functions.invoke('mela-ai-execution-v2',{body:{message:text}})
  if(invokeError){const detail=invokeError.context instanceof Response?await invokeError.context.clone().json().catch(()=>null):null;throw new Error(detail?.error||invokeError.message)}
  if(data?.mode==='approval_required'){setSuccess(data.task_id?`Approval required for task ${data.task_id}.`:'This request requires approval. No action has been executed.');return}
  if(!data?.ok||typeof data.response!=='string'||!data.response.trim())throw new Error(data?.error||'AI returned no usable response. Your request is preserved.')
  setAnswer(data.response);setMessage('');setSuccess('AI response received.');setRevision(v=>v+1)
 })
 const review=(status:'approved'|'rejected')=>run(async()=>{
  if(!selected||note.trim().length<5)return
  await reviewAIApproval(client,selected.id,status,note.trim());setSelected(null);setNote('');setSuccess(status==='approved'?'Approval saved. The requester must resume the task; approval does not execute it.':'Rejection saved and audited.');setRevision(v=>v+1)
 })
 return <section className="panel">
  <div className="module-head"><div><h2>AI Workforce</h2><p>Agent controls, approval decisions and execution history.</p></div><button disabled={loading||busy} onClick={()=>setRevision(v=>v+1)}>Refresh AI workforce</button></div>
  {loading&&<p role="status">Loading AI workforce…</p>}
  {error&&<div className="error" role="alert">{error}<button disabled={loading||busy} onClick={()=>setRevision(v=>v+1)}>Retry AI workforce</button></div>}
  {success&&<p role="status">{success}</p>}
  <form onSubmit={e=>{e.preventDefault();void execute()}} className="detail-card"><h3>Run an AI task</h3><label>AI task<textarea value={message} onChange={e=>setMessage(e.target.value)} maxLength={6000} disabled={busy} rows={3}/></label><button disabled={busy||!message.trim()}>{busy?'Saving…':'Run AI'}</button>{answer&&<div style={{whiteSpace:'pre-wrap'}}>{answer}</div>}</form>
  {ready&&<>
   <h3>Agents ({agents.length})</h3>
   {!agents.length&&<p>No agents are configured.</p>}
   {agents.map(agent=><div className="detail-card" key={agent.id}><strong>{agent.name}</strong><p>{agent.description}</p><p>{agent.domain} · autonomy {agent.autonomy_level} · {agent.max_steps} steps · {agent.timeout_seconds}s timeout</p><button disabled={busy||loading} onClick={()=>void run(async()=>{await setAgentEnabled(client,agent.id,!agent.enabled);setSuccess('Agent setting saved and audited.');setRevision(v=>v+1)})}>{agent.enabled?'Disable':'Enable'} {agent.name}</button></div>)}
   <h3>Approval history</h3><label>Approval status<select disabled={busy} value={approvalStatus} onChange={e=>{setApprovalStatus(e.target.value);setApprovalPage(0);setSelected(null);setNote('')}}>{['pending','approved','rejected'].map(s=><option key={s}>{s}</option>)}</select></label>
   {approvals.data.length===0&&<p>No {approvalStatus} approvals.</p>}
   {approvals.data.map(a=><div className="detail-card" key={a.id}><strong>{a.action_type}</strong><p>Level {a.level} · {a.status} · {new Date(a.created_at).toLocaleString()}</p><button disabled={busy} onClick={()=>{setSelected(a);setNote('')}}>Inspect approval {a.id}</button></div>)}
   <Pagination name="approvals" page={approvalPage} total={approvals.total} disabled={busy||loading} onPage={p=>{setApprovalPage(p);setSelected(null);setNote('')}}/>
   {selected&&<section className="detail-card" aria-label="Approval details"><h3>{selected.action_type}</h3><p>Requester: {selected.requested_by}</p><p>Task: {selected.task_id}</p><pre style={{whiteSpace:'pre-wrap',overflowWrap:'anywhere'}}>{JSON.stringify(selected.action_payload,null,2)}</pre>{selected.review_note&&<p>Review note: {selected.review_note}</p>}{selected.status==='pending'&&<><label>Review reason<textarea value={note} onChange={e=>setNote(e.target.value)} maxLength={1000} disabled={busy}/></label><p>Approval queues the task for its requester. It does not execute an action.</p><button disabled={busy||note.trim().length<5} onClick={()=>void review('approved')}>Approve request</button>{' '}<button disabled={busy||note.trim().length<5} onClick={()=>void review('rejected')}>Reject request</button></>}<button disabled={busy} onClick={()=>setSelected(null)}>Close approval</button></section>}
   <h3>Run history</h3><label>Run status<select value={runStatus} disabled={busy} onChange={e=>{setRunStatus(e.target.value);setRunPage(0);setRunDetail(null)}}><option value="">All statuses</option>{['running','completed','failed'].map(s=><option key={s}>{s}</option>)}</select></label>
   <div className="table-wrap"><table><thead><tr><th>Time</th><th>Agent</th><th>Model</th><th>Status</th><th>Steps</th><th>Details</th></tr></thead><tbody>{runs.data.map(r=><tr key={r.id}><td>{new Date(r.created_at).toLocaleString()}</td><td>{agents.find(a=>a.id===r.agent_id)?.name??r.agent_id}</td><td>{r.model}</td><td>{r.status}</td><td>{r.step_count}</td><td><button onClick={()=>setRunDetail(r)}>Inspect run {r.id}</button></td></tr>)}</tbody></table></div>
   {runs.data.length===0&&<p>No runs match this status.</p>}
   <Pagination name="runs" page={runPage} total={runs.total} disabled={busy||loading} onPage={p=>{setRunPage(p);setRunDetail(null)}}/>
   {runDetail&&<div className="detail-card"><h3>Run details</h3><p>ID: {runDetail.id}</p><p>Route: {runDetail.route_class} · latency: {runDetail.latency_ms??'—'} ms</p><p>Completed: {runDetail.completed_at?new Date(runDetail.completed_at).toLocaleString():'—'}</p>{runDetail.error_message&&<p role="alert">{runDetail.error_message}</p>}<button onClick={()=>setRunDetail(null)}>Close run</button></div>}
  </>}
 </section>
}
