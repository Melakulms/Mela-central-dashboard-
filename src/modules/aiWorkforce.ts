import { supabase } from '../lib/supabase';

export type Agent = { id:string; agent_key:string; name:string; domain:string; description:string; enabled:boolean; autonomy_level:number; max_steps:number; timeout_seconds:number; updated_at?:string };
export type Approval = { id:string; task_id:string; requested_by:string; level:number; action_type:string; action_payload:any; status:string; created_at:string; reviewed_by?:string|null; reviewed_at?:string|null; review_note?:string|null };
export type AIRun = { id:string; agent_id:string; user_id:string; model:string; route_class:string; step_count:number; status:string; latency_ms?:number|null; created_at:string; completed_at?:string|null };

async function aiAdmin<T>(action:string, body:Record<string,unknown>={}):Promise<T>{
  const {data:{session}}=await supabase.auth.getSession();
  if(!session) throw new Error('Authentication required');
  const {data,error}=await supabase.functions.invoke('mela-ai-admin',{body:{action,...body},headers:{'x-request-id':crypto.randomUUID()}});
  if(error) throw error;
  if(data?.error) throw Object.assign(new Error(data.error),{code:data.code});
  return data as T;
}

export async function getAIAgents(){
  const {data}=await aiAdmin<{data:Agent[]}>('agents.list'); return data??[];
}
export async function getAIPendingApprovals(){
  const {data}=await aiAdmin<{data:Approval[]}>('approvals.list'); return data??[];
}
export async function getAIRuns(limit=100){
  const {data}=await aiAdmin<{data:AIRun[]}>('runs.list',{limit}); return data??[];
}
export async function setAgentEnabled(id:string, enabled:boolean){
  await aiAdmin('agent.toggle',{agent_id:id,enabled});
}
export async function reviewAIApproval(id:string,status:'approved'|'rejected',review_note=''){
  await aiAdmin('approval.review',{approval_id:id,status,review_note});
}
export async function getAIOverview(){
  const [agents, approvals, runs] = await Promise.all([getAIAgents(),getAIPendingApprovals(),getAIRuns(100)]);
  const today=new Date().toISOString().slice(0,10);
  return {totalAgents:agents.length,activeAgents:agents.filter(a=>a.enabled).length,pendingApprovals:approvals.length,runsToday:runs.filter(r=>r.created_at.slice(0,10)===today).length,successfulRuns:runs.filter(r=>r.status==='completed').length,failedRuns:runs.filter(r=>r.status==='failed').length};
}
