import { supabase } from '../lib/supabase';

export type Agent = { id:string; agent_key:string; name:string; domain:string; description:string; enabled:boolean; autonomy_level:number; max_steps:number; timeout_seconds:number };
export type Approval = { id:string; task_id:string; requested_by:string; level:number; action_type:string; action_payload:any; status:string; created_at:string; review_note?:string|null };
export type AIRun = { id:string; agent_id:string; user_id:string; model:string; route_class:string; step_count:number; status:string; latency_ms?:number|null; created_at:string; completed_at?:string|null };

export async function getAIAgents(){
  const { data, error } = await supabase.from('mela_ai_agents').select('id,agent_key,name,domain,description,enabled,autonomy_level,max_steps,timeout_seconds').order('domain').order('name');
  if(error) throw error; return (data ?? []) as Agent[];
}
export async function getAIPendingApprovals(){
  const { data, error } = await supabase.from('mela_ai_approvals').select('*').eq('status','pending').order('created_at',{ascending:false});
  if(error) throw error; return (data ?? []) as Approval[];
}
export async function getAIRuns(limit=100){
  const { data, error } = await supabase.from('mela_ai_runs').select('*').order('created_at',{ascending:false}).limit(limit);
  if(error) throw error; return (data ?? []) as AIRun[];
}
export async function setAgentEnabled(id:string, enabled:boolean){
  const { error } = await supabase.from('mela_ai_agents').update({enabled,updated_at:new Date().toISOString()}).eq('id',id);
  if(error) throw error;
}
export async function reviewAIApproval(id:string,status:'approved'|'rejected',review_note=''){
  const { data: { user } } = await supabase.auth.getUser();
  if(!user) throw new Error('Authentication required');
  const { error } = await supabase.from('mela_ai_approvals').update({status,reviewed_by:user.id,reviewed_at:new Date().toISOString(),review_note}).eq('id',id).eq('status','pending');
  if(error) throw error;
  const { data: approval } = await supabase.from('mela_ai_approvals').select('task_id').eq('id',id).single();
  if(approval?.task_id) await supabase.from('mela_ai_tasks').update({approval_status:status,status:status==='approved'?'queued':'cancelled',updated_at:new Date().toISOString()}).eq('id',approval.task_id);
}
export async function getAIOverview(){
  const [agents, approvals, runs] = await Promise.all([getAIAgents(),getAIPendingApprovals(),getAIRuns(100)]);
  return {totalAgents:agents.length,activeAgents:agents.filter(a=>a.enabled).length,pendingApprovals:approvals.length,runsToday:runs.filter(r=>r.created_at.slice(0,10)===new Date().toISOString().slice(0,10)).length,successfulRuns:runs.filter(r=>r.status==='completed').length,failedRuns:runs.filter(r=>r.status==='failed').length};
}
