import type { SupabaseClient } from '@supabase/supabase-js'
import { invokeAdminFunction } from '../lib/admin-api'
export type Agent = { id:string; agent_key:string; name:string; domain:string; description:string; enabled:boolean; autonomy_level:number; max_steps:number; timeout_seconds:number }
export type Approval = { id:string; task_id:string; requested_by:string; level:number; action_type:string; action_payload:unknown; status:string; created_at:string; reviewed_by?:string|null; reviewed_at?:string|null; review_note?:string|null }
export type AIRun = { id:string; agent_id:string; user_id:string; model:string; route_class:string; step_count:number; status:string; latency_ms?:number|null; error_message?:string|null; created_at:string; completed_at?:string|null }
export type AIPage<T> = { data:T[]; total:number }
export async function getAIAgents(client:SupabaseClient):Promise<Agent[]> {
 const result=await invokeAdminFunction(client,'mela-ai-admin','agents.list');return result.data??[]
}
export async function getAIApprovals(client:SupabaseClient,offset=0,status='pending'):Promise<AIPage<Approval>> {
 return invokeAdminFunction(client,'mela-ai-admin','approvals.list',{offset,limit:25,status})
}
export async function getAIRuns(client:SupabaseClient,offset=0,status=''):Promise<AIPage<AIRun>> {
 return invokeAdminFunction(client,'mela-ai-admin','runs.list',{offset,limit:25,status})
}
export async function setAgentEnabled(client:SupabaseClient,id:string,enabled:boolean) {
 return invokeAdminFunction(client,'mela-ai-admin','agent.toggle',{agent_id:id,enabled})
}
export async function reviewAIApproval(client:SupabaseClient,id:string,status:'approved'|'rejected',review_note:string) {
 return invokeAdminFunction(client,'mela-ai-admin','approval.review',{approval_id:id,status,review_note})
}
