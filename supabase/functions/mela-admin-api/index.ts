import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.116.0'

const cors = { 'Access-Control-Allow-Origin': Deno.env.get('ADMIN_APP_ORIGIN') ?? 'https://central-dashboard-gamma.vercel.app', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-request-id', 'Access-Control-Allow-Methods': 'POST, OPTIONS' }
const safeCount = async (db: any, table: string, column = 'id') => { const { count, error } = await db.from(table).select(column, { count: 'exact', head: true }); return error ? null : count }
const cleanSearch = (value: unknown) => String(value ?? '').trim().slice(0, 200).replace(/[^\p{L}\p{N}@+ .-]/gu, '')
const limitOf = (value: unknown, max = 100) => { const number = Number(value ?? 50); return Number.isFinite(number) ? Math.min(Math.max(Math.trunc(number), 1), max) : 50 }



Deno.serve(async (req) => {
  const origin=req.headers.get('Origin')
  const allowedOrigins=new Set(['https://melakulms.github.io','https://central-dashboard-gamma.vercel.app',Deno.env.get('ADMIN_APP_ORIGIN')].filter(Boolean))
  const responseCors={...cors,'Access-Control-Allow-Origin':origin && allowedOrigins.has(origin)?origin:'https://melakulms.github.io','Vary':'Origin'}
  const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {status,headers:{...responseCors,'Content-Type':'application/json','Cache-Control':'no-store'}})
  if(origin&&!allowedOrigins.has(origin))return json({error:'Origin is not allowed'},403)
  const requestId = req.headers.get('x-request-id') ?? crypto.randomUUID()
  try {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: responseCors })
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405)
  const authHeader = req.headers.get('Authorization')
  if (!authHeader?.startsWith('Bearer ')) return json({ error: 'Authentication required' }, 401)
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  const caller = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authHeader } }, auth: { persistSession: false, autoRefreshToken: false } })
  const adminDb = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } })
  const { data: { user }, error: userError } = await caller.auth.getUser()
  if (userError || !user) return json({ error: 'Invalid session' }, 401)
  const { data: adminUser, error: adminError } = await adminDb.schema('admin').from('admin_users').select('user_id, role_id, active, mfa_required').eq('user_id', user.id).eq('active', true).maybeSingle()
  if (adminError || !adminUser) return json({ error: 'Admin access denied' }, 403)
  const { data: role, error: roleError } = await adminDb.schema('admin').from('roles').select('key,name').eq('id', adminUser.role_id).single()
  if (roleError || !role) return json({ error: 'Admin role is invalid' }, 403)
  const { data: assurance, error: assuranceError } = await caller.auth.mfa.getAuthenticatorAssuranceLevel(authHeader.slice(7))
  if (assuranceError) return json({ error: 'Unable to verify session assurance' }, 401)
  if (adminUser.mfa_required && assurance?.currentLevel !== 'aal2') return json({ error: 'MFA required', code: 'MFA_REQUIRED' }, 403)
  const { data: rolePermissions, error: permissionError } = await adminDb.schema('admin').from('role_permissions').select('permission_id').eq('role_id', adminUser.role_id)
  if (permissionError) return json({ error: 'Permission resolution failed' }, 500)
  const ids = (rolePermissions ?? []).map((row: any) => row.permission_id)
  const { data: permissionRows, error: permissionRowsError } = ids.length ? await adminDb.schema('admin').from('permissions').select('key').in('id', ids) : { data: [] as any[], error: null }
  if (permissionRowsError) return json({ error: 'Permission resolution failed' }, 500)
  const permissions = (permissionRows ?? []).map((row: any) => row.key).filter(Boolean)
  const body = await req.json().catch(() => null)
  if (!body || typeof body !== 'object' || Array.isArray(body) || typeof body.action !== 'string') return json({ error: 'A JSON object with an action is required' }, 400)
  const action = body.action
  const isSuper = role.key === 'super_admin'
  const allowed = (permission: string) => isSuper || permissions.includes(permission)
  const auditedUpdate = async (target: string, expected: any, patch: any, metadata: any = {}) => {
    if (body.expected_updated_at !== undefined && body.expected_updated_at !== expected.updated_at) return json({error:'Record changed; refresh before retrying',code:'STALE_RECORD'},409)
    const { data, error } = await adminDb.schema('admin').rpc('apply_audited_update', {
      p_actor: user.id, p_action: action, p_target: target, p_expected: expected,
      p_patch: patch, p_request_id: requestId, p_metadata: metadata,
    })
    if (error) {
      const status = error.code === '40001' ? 409 : error.code === 'P0002' ? 404 : error.code === '42501' ? 403 : error.code === '22023' ? 400 : 500
      return json({ error: status === 409 ? 'Record changed; refresh before retrying' : 'The update was not applied. Refresh the record before retrying.', code: 'ADMIN_UPDATE_FAILED', request_id: requestId }, status)
    }
    return json({ data })
  }
  if (action === 'me') return json({ user:{id:user.id,email:user.email}, role, permissions, mfa:assurance })

  if (action === 'dashboard') {
    if (!allowed('dashboard.read') && !allowed('platform.read')) return json({ error:'Permission denied' },403)
    const specs = [['users','profiles','id'],['payments','payments','id'],['payouts','payout_requests','id'],['employer_registrations','employer_registration_requests','id'],['opportunities','opportunities','id'],['reports','reports','id'],['integrity_events','arena_integrity_events','id'],['feature_flags','platform_feature_flags','feature_key']] as const
    const counts = await Promise.all(specs.map(async ([key,table,col]) => [key, await safeCount(adminDb,table,col)]))
    const userRoles = ['student','parent','teacher','employer','company','mentor','admin']
    const usersByRole = await Promise.all(userRoles.map(async (roleName) => ({ role: roleName, count: await (async () => { const { count, error } = await adminDb.from('profiles').select('id', { count:'exact', head:true }).eq('role', roleName); return error ? null : (count ?? 0) })() })))
    return json({ metrics:{table_counts:Object.fromEntries(counts),users_by_role:usersByRole}, generated_at:new Date().toISOString() })
  }

  if (action === 'queues') {
    if (!allowed('dashboard.read') && !allowed('platform.read')) return json({ error:'Permission denied' },403)
    const queues: Record<string,unknown[]> = {}
    const load = async (key:string, table:string, statuses:string[], permission:string) => { if (!allowed(permission)) return; const {data,error}=await adminDb.from(table).select('*').in('status',statuses).order('created_at',{ascending:false}).limit(50); queues[key]=error?[]:(data??[]) }
    await load('employer_registrations','employer_registration_requests',['pending','under_review','review','review_required'],'employers.manage')
    await load('opportunities','opportunities',['pending_review','review','flagged'],'employers.manage')
    await load('reports','reports',['pending','open','review','reviewing','escalated'],'moderation.manage')
    await load('payouts','payout_requests',['pending','queued','failed','review'],'finance.manage')
    if (allowed('moderation.manage')) {
    const {data:attempts}=await adminDb.from('assessment_attempts').select('*').in('proctor_status',['pending_review','review','flagged']).order('started_at',{ascending:false}).limit(50); queues.proctor_reviews=attempts??[]
    const {data:integrity}=await adminDb.from('arena_integrity_events').select('*').gte('severity',2).order('created_at',{ascending:false}).limit(50); queues.arena_integrity=integrity??[]
    }
    return json(queues)
  }

  if (action === 'users.list') {
    if (!allowed('users.read')) return json({error:'Permission denied'},403)
    const limit=limitOf(body.limit,100), offset=Number.isFinite(Number(body.offset??0))?Math.max(Math.trunc(Number(body.offset??0)),0):0
    let query=adminDb.from('profiles').select('id,full_name,email,phone_number,role,region,city,account_status,email_verified,phone_verified,profile_completion,created_at,updated_at,deleted_at,availability_status',{count:'exact'}).order('created_at',{ascending:false}).range(offset,offset+limit-1)
    if(body.role) query=query.eq('role',body.role)
    if(body.status) query=query.eq('account_status',body.status)
    const search=cleanSearch(body.search); if(search) query=query.or(`full_name.ilike.%${search}%,email.ilike.%${search}%,phone_number.ilike.%${search}%`)
    const {data,error,count}=await query; if(error)return json({error:'Unable to load users'},500)
    return json({data:data??[],total:count??0,offset,limit})
  }

  if (action === 'user.inspect') {
    if (!allowed('users.read')) return json({error:'Permission denied'},403)
    const userId=String(body.user_id??''); if(!userId)return json({error:'User ID is required'},400)
    const [{data:profile,error:profileError},{data:authUser,error:authError}]=await Promise.all([adminDb.from('profiles').select('*').eq('id',userId).maybeSingle(),adminDb.auth.admin.getUserById(userId)])
    if(profileError)return json({error:'Unable to inspect user'},500); if(!profile&&(authError||!authUser?.user))return json({error:'User not found'},404)
    const au=authUser?.user; return json({data:{profile:profile??null,auth:au?{id:au.id,email:au.email,phone:au.phone,email_confirmed_at:au.email_confirmed_at,phone_confirmed_at:au.phone_confirmed_at,created_at:au.created_at,last_sign_in_at:au.last_sign_in_at,banned_until:au.banned_until}:null}})
  }

  if (action === 'user.update') {
    if (!allowed('users.manage')) return json({error:'Permission denied'},403)
    const userId=String(body.user_id??''); const nextStatus=body.account_status===undefined?undefined:String(body.account_status); const statuses=['active','suspended','pending_verification','banned','deleted']
    if(!userId)return json({error:'User ID is required'},400); if(nextStatus!==undefined&&!statuses.includes(nextStatus))return json({error:'Invalid account status'},400); if(userId===user.id&&nextStatus&&nextStatus!=='active')return json({error:'You cannot deactivate or suspend your current admin account here'},409)
    const {data:existing,error:readError}=await adminDb.from('profiles').select('id,account_status,email_verified,phone_verified,updated_at').eq('id',userId).maybeSingle(); if(readError)return json({error:'Unable to read user'},500); if(!existing)return json({error:'User not found'},404)
    const patch:Record<string,unknown>={}; if(nextStatus!==undefined)patch.account_status=nextStatus; for(const field of ['email_verified','phone_verified']) { if(body[field]!==undefined) { if(typeof body[field]!=='boolean')return json({error:'Verification fields require true or false'},400); patch[field]=body[field] } } if(!Object.keys(patch).length)return json({error:'No supported changes supplied'},400)

    return auditedUpdate(userId,existing,patch,{changed_fields:Object.keys(patch)})
  }

  if (action === 'employers.list') {
    if (!allowed('employers.manage')) return json({error:'Permission denied'},403)
    const status=body.status; let q=adminDb.from('employer_registration_requests').select('*').order('created_at',{ascending:false}).limit(limitOf(body.limit,100)); if(status)q=q.eq('status',status); const {data,error}=await q; if(error)return json({error:'Unable to load employer registrations'},500); return json({data:data??[]})
  }
  if (action === 'employers.accounts') {
    if (!allowed('employers.manage')) return json({error:'Permission denied'},403)
    const {data,error}=await adminDb.from('employers').select('id,owner_id,company_name,legal_name,registration_number,sector_category,verified,verification_status,verification_notes,verified_by,verified_at,updated_at,created_at').order('created_at',{ascending:false}).limit(limitOf(body.limit,100))
    if(error)return json({error:'Unable to load employer accounts'},500)
    return json({data:data??[]})
  }
  if (action === 'employer.verify') {
    if (!allowed('employers.manage')) return json({error:'Permission denied'},403)
    const id=String(body.employer_id??''); const status=String(body.verification_status??''); const notes=String(body.verification_notes??'').trim()
    if(!id||!['verified','under_review','rejected','suspended'].includes(status)||!notes||notes.length>2000)return json({error:'Employer, verification decision and reason are required'},400)
    const {data:existing,error}=await adminDb.from('employers').select('*').eq('id',id).maybeSingle()
    if(error)return json({error:'Unable to read employer'},500)
    if(!existing)return json({error:'Employer not found'},404)
    return auditedUpdate(id,existing,{verified:status==='verified',verification_status:status,verification_notes:notes,verified_by:user.id,verified_at:status==='verified'?new Date().toISOString():null,updated_at:new Date().toISOString()},{status})
  }
  if (action === 'employer.review') {
    if (!allowed('employers.manage')) return json({error:'Permission denied'},403)
    const id=String(body.request_id??''); const next=String(body.status??''); const notes=String(body.review_notes??'').trim(); if(notes.length>2000)return json({error:'Review reason is too long'},400); if(['approved','rejected'].includes(next)&&!notes)return json({error:'Review reason is required'},400); if(!id||!['approved','rejected','pending','under_review'].includes(next))return json({error:'Request ID and valid status are required'},400)
    const {data:existing,error:r}=await adminDb.from('employer_registration_requests').select('*').eq('id',id).maybeSingle(); if(r)return json({error:'Unable to read employer request'},500); if(!existing)return json({error:'Employer request not found'},404)
    return auditedUpdate(id,existing,{status:next,review_notes:notes||null,reviewed_by:user.id,reviewed_at:new Date().toISOString(),updated_at:new Date().toISOString()},{status:next})
  }

  if (action === 'opportunities.list') {
    if (!allowed('employers.manage')) return json({error:'Permission denied'},403)
    let q=adminDb.from('opportunities').select('id,title,organization_name,employer_id,status,moderation_status,verified_active,created_at,updated_at,deadline,reviewed_by,reviewed_at').order('created_at',{ascending:false}).limit(limitOf(body.limit,100)); if(body.status)q=q.eq('status',body.status); if(body.moderation_status)q=q.eq('moderation_status',body.moderation_status); const {data,error}=await q; if(error)return json({error:'Unable to load opportunities'},500); return json({data:data??[]})
  }
  if (action === 'opportunity.review') {
    if (!allowed('employers.manage')) return json({error:'Permission denied'},403)
    const id=String(body.opportunity_id??''); const status=String(body.moderation_status??''); const notes=String(body.moderation_notes??'').trim(); if(notes.length>2000)return json({error:'Moderation reason is too long'},400); if(['approved','rejected'].includes(status)&&!notes)return json({error:'Moderation reason is required'},400); if(!id||!['approved','rejected','pending_review','flagged'].includes(status))return json({error:'Opportunity ID and valid moderation status are required'},400)
    const {data:existing,error:r}=await adminDb.from('opportunities').select('*').eq('id',id).maybeSingle(); if(r)return json({error:'Unable to read opportunity'},500); if(!existing)return json({error:'Opportunity not found'},404)
    const patch:any={moderation_status:status,moderation_notes:notes||null,reviewed_by:user.id,reviewed_at:new Date().toISOString(),updated_at:new Date().toISOString()}; patch.verified_active=status==='approved'
    return auditedUpdate(id,existing,patch,{status})
  }

  if (action === 'disputes.list') {
    if (!allowed('support.manage')) return json({error:'Permission denied'},403)
    const limit=limitOf(body.limit)
    const [reports,contracts]=await Promise.all([
      adminDb.from('reports').select('id,reporter_id,target_id,details,status,created_at,resolution_notes').eq('target_type','freelance_contract').eq('reason','contract_dispute').order('created_at',{ascending:false}).limit(limit),
      adminDb.from('freelance_contracts').select('id,task_id,employer_id,freelancer_id,status,funding_status,agreed_amount,currency,updated_at').eq('status','disputed').order('updated_at',{ascending:false}).limit(limit),
    ])
    if(reports.error||contracts.error)return json({error:'Dispute records unavailable'},500)
    return json({reports:reports.data??[],contracts:contracts.data??[]})
  }

  if (action === 'payments.list') {
    if (!allowed('finance.manage')) return json({error:'Permission denied'},403)
    let q=adminDb.from('payments').select('id,user_id,course_id,provider,mode,tx_ref,provider_ref,expected_amount_cents,expected_currency,status,provider_status,provider_method,provider_type,provider_charge,failure_reason,created_at,updated_at,paid_at,last_verified_at').order('created_at',{ascending:false}).limit(limitOf(body.limit,200)); if(body.status)q=q.eq('status',body.status); const search=cleanSearch(body.search); if(search)q=q.or(`tx_ref.ilike.%${search}%,provider_ref.ilike.%${search}%`); const {data,error}=await q; if(error)return json({error:'Unable to load payments'},500); return json({data:data??[]})
  }
  if (action === 'payouts.list') {
    if (!allowed('finance.manage')) return json({error:'Permission denied'},403)
    let q=adminDb.from('payout_requests').select('id,milestone_id,escrow_id,freelancer_id,amount_minor,currency,provider,payout_ref,status,provider_ref,failure_reason,created_at,updated_at,completed_at').order('created_at',{ascending:false}).limit(limitOf(body.limit,200)); if(body.status)q=q.eq('status',body.status); const {data,error}=await q; if(error)return json({error:'Unable to load payouts'},500); return json({data:data??[]})
  }

  if (action === 'moderation.list') {
    if (!allowed('moderation.manage')) return json({error:'Permission denied'},403)
    const [reports,integrity,flaggedOpportunities]=await Promise.all([adminDb.from('reports').select('*').in('status',['pending','open','review','reviewing','escalated']).order('created_at',{ascending:false}).limit(50),adminDb.from('arena_integrity_events').select('*').gte('severity',2).order('created_at',{ascending:false}).limit(50),adminDb.from('opportunities').select('id,title,organization_name,status,moderation_status,moderation_notes,created_at').in('moderation_status',['flagged','pending_review','rejected']).order('created_at',{ascending:false}).limit(50)])
    if(reports.error||integrity.error||flaggedOpportunities.error)return json({error:'Moderation records unavailable. Please retry.'},500)
    return json({reports:reports.data??[],integrity_events:integrity.data??[],flagged_opportunities:flaggedOpportunities.data??[]})
  }
  if (action === 'report.resolve') {
    if (!allowed('moderation.manage')) return json({error:'Permission denied'},403)
    const id=String(body.report_id??''); const status=String(body.status??'resolved'); const notes=String(body.resolution_notes??'').trim(); if(!id||!['resolved','dismissed','reviewing'].includes(status))return json({error:'Report ID and valid status are required'},400)
    const {data:existing,error:r}=await adminDb.from('reports').select('*').eq('id',id).maybeSingle(); if(r)return json({error:'Unable to read report'},500); if(!existing)return json({error:'Report not found'},404)
    if(existing.target_type==='freelance_contract'||existing.reason==='contract_dispute')return json({error:'Contract disputes require settlement review in Disputes; general moderation cannot close them.',code:'DISPUTE_SETTLEMENT_REQUIRED'},409)
    if(!['open','reviewing'].includes(existing.status))return json({error:'Report is already closed or cannot be reviewed. Refresh before retrying.'},409)
    if(notes.length>2000||(['resolved','dismissed'].includes(status)&&!notes))return json({error:'A resolution reason of 1–2000 characters is required'},400)
    return auditedUpdate(id,existing,{status,resolution_notes:notes||null,assigned_to:user.id,resolved_at:status==='resolved'||status==='dismissed'?new Date().toISOString():null},{status})
  }

  if (action === 'settings.flags') {
    if (!allowed('system.manage')) return json({error:'Permission denied'},403)
    const {data,error}=await adminDb.from('platform_feature_flags').select('*').order('feature_key'); if(error)return json({error:'Unable to load feature flags'},500); return json({data:data??[]})
  }
  if (action === 'settings.flag.update') {
    if (!allowed('system.manage')) return json({error:'Permission denied'},403)
    const featureKey=String(body.feature_key??''); if(!featureKey)return json({error:'Feature key is required'},400); const {data:existing,error:r}=await adminDb.from('platform_feature_flags').select('*').eq('feature_key',featureKey).maybeSingle(); if(r)return json({error:'Unable to read feature flag'},500); if(!existing)return json({error:'Feature flag not found'},404)
    const patch:any={}; if(body.enabled!==undefined){if(typeof body.enabled!=='boolean')return json({error:'Enabled must be true or false'},400);patch.enabled=body.enabled;} if(body.maintenance_message!==undefined)patch.maintenance_message=String(body.maintenance_message); if(body.config!==undefined)patch.config=body.config; patch.updated_by=user.id; patch.updated_at=new Date().toISOString(); return auditedUpdate(featureKey,existing,patch,{changed_fields:Object.keys(patch)})
  }

  if (action === 'commission.list') {
    if (!allowed('finance.manage')) return json({error:'Permission denied'},403); const limit=limitOf(body.limit,200); let q=adminDb.from('invitation_commissions').select('*').order('created_at',{ascending:false}).limit(limit); if(body.status)q=q.eq('status',body.status); const search=cleanSearch(body.search); if(search)q=q.or(`invitation_code.ilike.%${search}%,transaction_reference.ilike.%${search}%`); const {data,error}=await q; if(error)return json({error:error.message},500); return json({data:data??[]})
  }
  if (action === 'commission.inspect') {
    if (!allowed('finance.manage')) return json({error:'Permission denied'},403); const id=String(body.commission_id??''); if(!id)return json({error:'Commission ID is required'},400); const {data,error}=await adminDb.from('invitation_commissions').select('*').eq('id',id).maybeSingle(); if(error)return json({error:error.message},500); if(!data)return json({error:'Commission not found'},404); return json({data})
  }
  if (action === 'commission.cancel') {
    if (!allowed('finance.manage')) return json({error:'Permission denied'},403); const id=String(body.commission_id??''); const reason=String(body.reason??'').trim(); if(!id||!reason)return json({error:'Commission ID and cancellation reason are required'},400); if(reason.length>500)return json({error:'Cancellation reason must be 500 characters or fewer'},400); const {data:existing,error:r}=await adminDb.from('invitation_commissions').select('*').eq('id',id).maybeSingle(); if(r)return json({error:r.message},500); if(!existing)return json({error:'Commission not found'},404); if(existing.status==='cancelled')return json({data:existing,already_cancelled:true}); if(existing.status==='paid')return json({error:'Paid commissions require a separate reversal workflow'},409); return auditedUpdate(id,existing,{status:'cancelled',cancelled_at:new Date().toISOString(),cancellation_reason:reason},{reason})
  }

  if (action === 'commission.summary') {
    if (!allowed('finance.manage')) return json({error:'Permission denied'},403)
    const {data,error}=await adminDb.from('invitation_commissions').select('status,amount')
    if(error)return json({error:error.message},500)
    const rows=data??[]
    const summary=rows.reduce((acc:any,row:any)=>{acc.total++;const amt=Number(row.amount||0);acc.total_amount+=amt;if(row.status==='pending')acc.pending++;if(row.status==='paid')acc.paid++;if(row.status==='cancelled')acc.cancelled++;return acc},{total:0,pending:0,paid:0,cancelled:0,total_amount:0})
    return json(summary)
  }

  if (action === 'authorization.matrix') {
    if (!allowed('authorization.manage')) return json({error:'Permission denied'},403); const [{data:roles,error:re},{data:allPermissions,error:pe},{data:mappings,error:me}]=await Promise.all([adminDb.schema('admin').from('roles').select('id,key,name,description,is_privileged').order('name'),adminDb.schema('admin').from('permissions').select('id,key,name,description').order('key'),adminDb.schema('admin').from('role_permissions').select('role_id,permission_id')]); if(re||pe||me)return json({error:'Authorization matrix unavailable'},500); return json({roles,permissions:allPermissions,mappings})
  }
  if (action === 'audit.list') { if(!allowed('audit.read'))return json({error:'Permission denied'},403); const {data,error}=await adminDb.schema('admin').from('audit_log').select('*').order('created_at',{ascending:false}).limit(limitOf(body.limit,200)); if(error)return json({error:error.message},500); return json({data:data??[]}) }
  if (action === 'access.list') {
    if(!allowed('authorization.manage'))return json({error:'Permission denied'},403)
    const {data,error}=await adminDb.schema('admin').from('access_requests').select('*').order('created_at',{ascending:false}).limit(100)
    if(error)return json({error:error.message},500)
    const rows=data??[]
    const roleIds=[...new Set(rows.map((r:any)=>r.requested_role_id).filter(Boolean))]
    let roleMap:Record<string,string>={}
    if(roleIds.length){const {data:roles}=await adminDb.schema('admin').from('roles').select('id,name').in('id',roleIds); roleMap=Object.fromEntries((roles??[]).map((r:any)=>[r.id,r.name]))}
    const enriched=rows.map((r:any)=>({...r,requester_user_id:r.requester_id,requested_role:roleMap[r.requested_role_id]??r.requested_role_id}))
    return json({data:enriched})
  }
  if (action === 'audit.append') { if(!allowed('authorization.manage'))return json({error:'Permission denied'},403); const audit=body.audit??{}; const {error}=await adminDb.schema('admin').from('audit_log').insert({actor_user_id:user.id,actor_role:role.key,action:audit.action??'admin.action',target_schema:audit.target_schema??null,target_table:audit.target_table??null,target_id:audit.target_id??null,before_data:audit.before_data??null,after_data:audit.after_data??null,metadata:{...(audit.metadata??{}),source:'mela-central-dashboard'},request_id:requestId}); if(error)return json({error:error.message},500); return json({ok:true}) }
  return json({error:'Unknown admin action'},400)
  } catch (error) {
    return json({ error: 'The request could not be completed. Refresh the record before retrying.', code: 'ADMIN_REQUEST_FAILED', request_id: requestId }, 500)
  }
})
