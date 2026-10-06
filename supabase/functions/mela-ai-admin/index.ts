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
 const {data:role,error:re}=await db.schema('admin').from('roles').select('key,name').eq('id',au.role_id).single(); if(re||!role)return json({error:'Admin role is invalid'},403,h)
 const {data:assurance,error:assuranceError}=await caller.auth.mfa.getAuthenticatorAssuranceLevel(ah.slice(7)); if(assuranceError||assurance?.currentLevel!=='aal2')return json({error:'MFA required',code:'MFA_REQUIRED'},403,h)
 const {data:rps,error:pe}=await db.schema('admin').from('role_permissions').select('permission_id').eq('role_id',au.role_id); if(pe)return json({error:'Permission resolution failed'},500,h)
 const ids=(rps??[]).map((r:any)=>r.permission_id); const {data:prs,error:permissionError}=ids.length?await db.schema('admin').from('permissions').select('key').in('id',ids):{data:[] as any[],error:null}; if(permissionError)return json({error:'Permission resolution failed'},500,h); const permissions=(prs??[]).map((r:any)=>r.key).filter(Boolean)
 const allowed=(p:string)=>role.key==='super_admin'||permissions.includes(p); const rid=req.headers.get('x-request-id')??crypto.randomUUID(); const body=await req.json().catch(()=>({})); const action=String(body.action??'')
 const audit=async(a:any)=>{await db.schema('admin').from('audit_log').insert({actor_user_id:user.id,actor_role:role.key,action:a.action,target_schema:a.schema??'public',target_table:a.table??null,target_id:a.id??null,before_data:a.before??null,after_data:a.after??null,metadata:{...(a.metadata??{}),source:'mela-ai-admin'},request_id:rid})}
 if(!allowed('system.manage'))return json({error:'Permission denied'},403,h)

 if(action==='agents.list'){
  const {data,error}=await db.from('mela_ai_agents').select('id,agent_key,name,domain,description,enabled,autonomy_level,max_steps,timeout_seconds,updated_at').order('domain').order('name');
  if(error)return json({error:'Unable to load AI agents'},500,h); return json({data:data??[]},200,h)
 }
 if(action==='runs.list'){
  const {data,error}=await db.from('mela_ai_runs').select('id,agent_id,user_id,model,route_class,step_count,status,latency_ms,created_at,completed_at').order('created_at',{ascending:false}).limit(limitOf(body.limit));
  if(error)return json({error:'Unable to load AI runs'},500,h); return json({data:data??[]},200,h)
 }
 if(action==='approvals.list'){
  const {data,error}=await db.from('mela_ai_approvals').select('id,task_id,requested_by,level,action_type,action_payload,status,created_at,reviewed_by,reviewed_at,review_note').eq('status','pending').order('created_at',{ascending:false}).limit(limitOf(body.limit));
  if(error)return json({error:'Unable to load AI approvals'},500,h); return json({data:data??[]},200,h)
 }
 if(action==='agent.toggle'){
  const id=String(body.agent_id??''); const enabled=body.enabled===true||body.enabled===false?body.enabled:null; if(!id||enabled===null)return json({error:'agent_id and enabled are required'},400,h)
  const {data:old,error:oe}=await db.from('mela_ai_agents').select('id,enabled').eq('id',id).maybeSingle(); if(oe)return json({error:'Unable to read agent'},500,h); if(!old)return json({error:'Agent not found'},404,h)
  const {data:updated,error}=await db.from('mela_ai_agents').update({enabled,updated_at:new Date().toISOString()}).eq('id',id).select('id,enabled,updated_at').maybeSingle(); if(error)return json({error:'Unable to update agent'},500,h)
  await audit({action:'ai.agent.toggle',table:'mela_ai_agents',id,before:old,after:updated,metadata:{enabled}}); return json({data:updated},200,h)
 }
 if(action==='approval.review'){
  const id=String(body.approval_id??''), status=String(body.status??''), note=String(body.review_note??'').trim(); if(!id||!['approved','rejected'].includes(status))return json({error:'approval_id and approved/rejected status are required'},400,h); if(note.length>1000)return json({error:'Review note too long'},400,h)
  const {data:old,error:oe}=await db.from('mela_ai_approvals').select('*').eq('id',id).eq('status','pending').maybeSingle(); if(oe)return json({error:'Unable to read approval'},500,h); if(!old)return json({error:'Pending approval not found'},404,h)
  const now=new Date().toISOString(); const {data:updated,error}=await db.from('mela_ai_approvals').update({status,reviewed_by:user.id,reviewed_at:now,review_note:note||null}).eq('id',id).eq('status','pending').select('*').maybeSingle(); if(error)return json({error:'Unable to review approval'},500,h); if(!updated)return json({error:'Approval changed concurrently'},409,h)
  let task=null; if(old.task_id){ const patch={approval_status:status,status:status==='approved'?'queued':'cancelled',updated_at:now}; const r=await db.from('mela_ai_tasks').update(patch).eq('id',old.task_id).select('id,status,approval_status,updated_at').maybeSingle(); task=r.data??null; if(r.error)return json({error:'Approval updated but task transition failed',code:'TASK_TRANSITION_FAILED'},500,h) }
  await audit({action:'ai.approval.review',table:'mela_ai_approvals',id,before:old,after:updated,metadata:{status,task_id:old.task_id??null}}); return json({data:updated,task},200,h)
 }
 return json({error:'Unknown AI admin action'},400,h)
})
