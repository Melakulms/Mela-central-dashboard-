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
 const allowed=(p:string)=>role.key==='super_admin'||permissions.includes(p); const rid=req.headers.get('x-request-id')??crypto.randomUUID(); const body=await req.json().catch(()=>null); if(!body||typeof body!=='object'||Array.isArray(body))return json({error:'JSON object required'},400,h); const action=String(body.action??'')
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
