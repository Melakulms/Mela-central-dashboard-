import { useEffect, useState } from 'react';
import { getAIAgents, getAIPendingApprovals, getAIRuns, reviewAIApproval, setAgentEnabled, type Agent, type Approval, type AIRun } from './aiWorkforce';

export default function AIWorkforcePanel(){
 const [agents,setAgents]=useState<Agent[]>([]); const [approvals,setApprovals]=useState<Approval[]>([]); const [runs,setRuns]=useState<AIRun[]>([]); const [loading,setLoading]=useState(true); const [error,setError]=useState('');
 const load=async()=>{try{setLoading(true);setError('');const [a,p,r]=await Promise.all([getAIAgents(),getAIPendingApprovals(),getAIRuns()]);setAgents(a);setApprovals(p);setRuns(r);}catch(e:any){setError(e?.message||'Unable to load AI workforce');}finally{setLoading(false)}};
 useEffect(()=>{load()},[]);
 const toggle=async(a:Agent)=>{try{await setAgentEnabled(a.id,!a.enabled);setAgents(x=>x.map(v=>v.id===a.id?{...v,enabled:!v.enabled}:v));}catch(e:any){setError(e?.message||'Unable to update agent')}};
 const review=async(id:string,status:'approved'|'rejected')=>{try{await reviewAIApproval(id,status);setApprovals(x=>x.filter(a=>a.id!==id));}catch(e:any){setError(e?.message||'Unable to review approval')}};
 if(loading)return <div className="p-6">Loading MELA AI Workforce…</div>;
 return <div className="space-y-6 p-6">
  <div><h1 className="text-2xl font-bold">MELA AI Workforce</h1><p className="text-sm opacity-70">Central control, approvals, agent status and execution monitoring.</p></div>
  {error&&<div className="rounded-lg border p-3 text-sm">{error}</div>}
  <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
   {[[agents.length,'Agents'],[agents.filter(a=>a.enabled).length,'Active'],[approvals.length,'Pending approvals'],[runs.filter(r=>r.status==='completed').length,'Completed runs']].map(([n,l])=><div key={String(l)} className="rounded-xl border p-4"><div className="text-2xl font-bold">{n}</div><div className="text-sm opacity-70">{l}</div></div>)}
  </div>
  <section className="rounded-xl border p-4"><h2 className="mb-4 text-lg font-semibold">Agent management</h2><div className="divide-y">{agents.map(a=><div key={a.id} className="flex items-center justify-between gap-4 py-3"><div><div className="font-medium">{a.name}</div><div className="text-xs opacity-60">{a.domain} · autonomy L{a.autonomy_level} · max {a.max_steps} steps</div></div><button onClick={()=>toggle(a)} className="rounded-lg border px-3 py-1.5 text-sm">{a.enabled?'Disable':'Enable'}</button></div>)}</div></section>
  <section className="rounded-xl border p-4"><h2 className="mb-4 text-lg font-semibold">Approval queue</h2>{approvals.length===0?<p className="text-sm opacity-60">No pending approvals.</p>:<div className="space-y-3">{approvals.map(a=><div key={a.id} className="rounded-lg border p-3"><div className="font-medium">{a.action_type}</div><div className="text-xs opacity-60">Level {a.level} · {new Date(a.created_at).toLocaleString()}</div><div className="mt-3 flex gap-2"><button onClick={()=>review(a.id,'approved')} className="rounded-lg border px-3 py-1.5 text-sm">Approve</button><button onClick={()=>review(a.id,'rejected')} className="rounded-lg border px-3 py-1.5 text-sm">Reject</button></div></div>)}</div>}</section>
  <section className="rounded-xl border p-4"><h2 className="mb-4 text-lg font-semibold">Recent AI runs</h2><div className="overflow-auto"><table className="w-full text-left text-sm"><thead><tr className="border-b"><th className="p-2">Time</th><th className="p-2">Model</th><th className="p-2">Route</th><th className="p-2">Status</th><th className="p-2">Steps</th></tr></thead><tbody>{runs.slice(0,25).map(r=><tr key={r.id} className="border-b"><td className="p-2">{new Date(r.created_at).toLocaleString()}</td><td className="p-2">{r.model}</td><td className="p-2">{r.route_class}</td><td className="p-2">{r.status}</td><td className="p-2">{r.step_count}</td></tr>)}</tbody></table></div></section>
 </div>
}
