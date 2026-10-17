import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.116.0'

const origins = new Set((Deno.env.get('ADMIN_APP_ORIGINS') ?? 'https://central-dashboard-gamma.vercel.app,https://mela-central-dashboard.netlify.app').split(',').map(x=>x.trim()).filter(Boolean))
origins.add('https://melakulms.github.io')
const cors = (req:Request) => { const o=req.headers.get('origin')??''; if(o && !origins.has(o)) return null; return {'Access-Control-Allow-Origin':o||'https://central-dashboard-gamma.vercel.app','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type, x-request-id','Access-Control-Allow-Methods':'POST, OPTIONS','Vary':'Origin'} }
const json=(b:unknown,s=200,h:Record<string,string>={})=>new Response(JSON.stringify(b),{status:s,headers:{'Content-Type':'application/json','Cache-Control':'no-store',...h}})
const limitOf=(v:unknown,m=200)=>{const n=Number(v??50);return Number.isFinite(n)?Math.min(Math.max(Math.trunc(n),1),m):50}

Deno.serve(async req=>{
 const h=cors(req); if(!h)return json({error:'Origin not allowed'},403)
 if(req.method==='OPTIONS')return new Response('ok',{headers:h}); if(req.method!=='POST')return json({error:'Method not allowed'},405,h)
 const ah=req.headers.get('Authorization'); if(!ah?.startsWith('Bearer '))return json({error:'Authentication required'},401,h)
 const url=Deno.env.get('SUPABASE_URL')!, anon=Deno.env.get('SUPABASE_ANON_KEY')!, service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
 const caller=createClient(url,anon,{global:{headers:{Authorization:ah}}}), db=createClient(url,service)
 const {data:{user},error:ue}=await caller.auth.getUser(); if(ue||!user)return json({error:'Invalid session'},401,h)
 const {data:au,error:ae}=await db.schema('admin').from('admin_users').select('user_id,role_id,active,mfa_required').eq('user_id',user.id).eq('active',true).maybeSingle(); if(ae||!au)return json({error:'Admin access denied'},403,h)
 const {data:profile,error:profileError}=await db.from('profiles').select('account_status,deleted_at').eq('id',user.id).maybeSingle();if(profileError||profile?.account_status!=='active'||profile.deleted_at!==null)return json({error:'Active administrator account required'},403,h);
 const {data:role,error:re}=await db.schema('admin').from('roles').select('key,name').eq('id',au.role_id).single(); if(re||!role)return json({error:'Admin role is invalid'},403,h)
 const {data:assurance,error:assuranceError}=await caller.auth.mfa.getAuthenticatorAssuranceLevel(ah.slice(7)); if(assuranceError||assurance?.currentLevel!=='aal2')return json({error:'MFA required',code:'MFA_REQUIRED'},403,h)
 const {data:rps,error:pe}=await db.schema('admin').from('role_permissions').select('permission_id').eq('role_id',au.role_id); if(pe)return json({error:'Permission resolution failed'},500,h)
 const ids=(rps??[]).map((r:any)=>r.permission_id); const {data:prs,error:permissionError}=ids.length?await db.schema('admin').from('permissions').select('key').in('id',ids):{data:[] as any[],error:null}; if(permissionError)return json({error:'Permission resolution failed'},500,h); const permissions=(prs??[]).map((r:any)=>r.key).filter(Boolean)
 const allowed=(p:string)=>role.key==='super_admin'||permissions.includes(p); const rid=req.headers.get('x-request-id')??crypto.randomUUID(); const body=await req.json().catch(()=>null); if(!body||typeof body!=='object'||Array.isArray(body))return json({error:'JSON object required'},400,h); const action=String(body.action??'')
 if(!allowed('system.manage'))return json({error:'Permission denied'},403,h)

 if(action==='agent.reply'){
  // Only an administrator who passed the registry, AAL2 and system.manage
  // checks above can request an individual worker's advisory response.
  // Worker execution is delegated with the *same user JWT*; no service key is
  // forwarded to the worker or exposed to the frontend.
  const agentId=String(body.agent_id??'');
  const prompt=typeof body.message==='string'?body.message.trim():'';
  if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(agentId))return json({error:'Select a valid AI worker'},400,h);
  if(!prompt||prompt.length>6000)return json({error:'Enter an AI task of 1–6000 characters'},400,h);
  if(!Deno.env.get('GROQ_API_KEY')?.trim()&&!Deno.env.get('MELA_AI_API_KEY')?.trim())return json({error:'AI provider is not configured. Add a free Groq API key in the Supabase GROQ_API_KEY secret. The task was not submitted.',code:'AI_PROVIDER_UNAVAILABLE'},503,h);
  const {data:worker,error:workerError}=await db.from('mela_ai_agents').select('id,agent_key,name,enabled').eq('id',agentId).eq('enabled',true).maybeSingle();
  if(workerError)return json({error:'Could not verify the selected worker'},503,h);
  if(!worker)return json({error:'Selected AI worker is disabled or not found'},404,h);
  const {data:task,error:taskError}=await db.from('mela_ai_tasks').insert({
   created_by:user.id,assigned_agent_id:worker.id,title:prompt.slice(0,140),
   description:prompt,priority:3,approval_level:1,status:'queued',
   approval_status:'not_required',retry_count:0,max_retries:2,verification_status:'pending',
  }).select('id').single();
  if(taskError||!task?.id)return json({error:'Could not queue the selected worker'},503,h);
  try{
   const execution=await fetch(url+'/functions/v1/mela-ai-execution-v2',{
    method:'POST',headers:{Authorization:ah,apikey:anon,'Content-Type':'application/json','x-request-id':rid.slice(0,200)},
    body:JSON.stringify({task_id:task.id}),signal:AbortSignal.timeout(55000),
   });
   const response=await execution.json().catch(()=>null);
   if(!execution.ok||response?.ok!==true)return json({
    error:execution.status===429?'AI daily limit reached. No AI answer was produced.':'AI worker could not complete the task. Check run history and provider configuration.',
    code:response?.code??'AI_WORKER_FAILED',task_id:task.id,
   },execution.status===429?429:503,h);
   return json({ok:true,response:response.response,task_id:task.id,run_id:response.run_id,agent:response.agent,tool:response.tool,advisory_only:true},200,h);
  }catch{
   return json({error:'AI worker connection timed out. Check run history before retrying.',code:'AI_WORKER_TIMEOUT',task_id:task.id},503,h);
  }
 }
 if(action==='health'){
  // Read-only, permission- and MFA-gated diagnostics. Never return secrets or
  // mark workers healthy merely because their database rows are enabled.
  const checks=await Promise.all([
   db.from('mela_ai_agents').select('id',{head:true,count:'exact'}).eq('enabled',true),
   db.from('mela_ai_agent_tools').select('agent_id',{head:true,count:'exact'}),
   db.from('mela_ai_runs').select('id',{head:true,count:'exact'}),
   db.from('mela_ai_tasks').select('id',{head:true,count:'exact'}),
  ]);
  if(checks.some(check=>check.error))return json({error:'AI health checks could not be completed'},503,h);
  const enabled_agents=checks[0].count??0,tool_assignments=checks[1].count??0,run_count=checks[2].count??0,task_count=checks[3].count??0;
  const groqReady=Boolean(Deno.env.get('GROQ_API_KEY')?.trim());
  const openaiReady=Boolean(Deno.env.get('MELA_AI_API_KEY')?.trim());
  const preference=Deno.env.get('MELA_AI_PROVIDER')?.toLowerCase();
  const provider=preference==='openai'?'openai':preference==='groq'?'groq':groqReady?'groq':openaiReady?'openai':'none';
  const provider_configured=provider==='groq'?groqReady:provider==='openai'?openaiReady:false;
  return json({
   provider_configured,provider,enabled_agents,tool_assignments,run_count,task_count,
   configuration_ready:provider_configured&&enabled_agents>0&&tool_assignments>0,
   execution_verified:false,
   note:'This checks configuration only; a successful authenticated, quota-allowed real AI response is required to verify execution.',
  },200,h);
 }
 if(action==='agents.list'){
  const {data,error}=await db.from('mela_ai_agents').select('id,agent_key,name,domain,description,enabled,autonomy_level,max_steps,timeout_seconds,updated_at').order('domain').order('name');
  if(error)return json({error:'Unable to load AI agents'},500,h); return json({data:data??[]},200,h)
 }
 if(action==='runs.list'||action==='approvals.list'){
  const limit=limitOf(body.limit,100), offset=Number(body.offset??0), status=String(body.status??(action==='approvals.list'?'pending':''));
  if(!Number.isSafeInteger(offset)||offset<0)return json({error:'offset must be a non-negative integer'},400,h);
  const allowedStatuses=action==='runs.list'?['running','completed','failed']:['pending','approved','rejected'];
  if(status&&!allowedStatuses.includes(status))return json({error:'Invalid status filter'},400,h);
  const table=action==='runs.list'?'mela_ai_runs':'mela_ai_approvals';
  const columns=action==='runs.list'?'id,agent_id,user_id,model,route_class,step_count,status,latency_ms,error_message,created_at,completed_at':'id,task_id,requested_by,level,action_type,action_payload,status,created_at,reviewed_by,reviewed_at,review_note';
  let query=db.from(table).select(columns,{count:'exact'}).order('created_at',{ascending:false}).order('id',{ascending:false});
  if(status)query=query.eq('status',status);
  const {data,error,count}=await query.range(offset,offset+limit-1);
  if(error)return json({error:'Unable to load AI history'},500,h);
  return json({data:data??[],total:count??0},200,h);
 }
 if(action==='agent.toggle'||action==='approval.review'){
  const id=String(action==='agent.toggle'?body.agent_id??'':body.approval_id??'');
  if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id))return json({error:'Valid target ID required'},400,h);
  if(action==='agent.toggle'&&typeof body.enabled!=='boolean')return json({error:'enabled must be a boolean'},400,h);
  if(action==='approval.review'&&!['approved','rejected'].includes(body.status))return json({error:'Invalid review status'},400,h);
  const {data,error}=await db.rpc('mela_ai_admin_mutate',{
   p_actor:user.id,p_action:action,p_target:id,p_request_id:rid.slice(0,200),
   p_enabled:action==='agent.toggle'?body.enabled:null,
   p_status:action==='approval.review'?body.status:null,
   p_note:action==='approval.review'?String(body.review_note??'').trim():null,
  });
  if(error){const status=error.code==='42501'?403:error.code==='40001'?409:error.code==='P0002'?404:error.code==='22023'?400:500;return json({error:'AI admin change was not saved',code:error.code},status,h)}
  return json(data,200,h);
 }
 return json({error:'Unknown AI admin action'},400,h)
})
