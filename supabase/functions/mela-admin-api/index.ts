import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2'

const cors = { 'Access-Control-Allow-Origin': Deno.env.get('ADMIN_APP_ORIGIN') ?? 'https://mela-central-dashboard.netlify.app', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-request-id', 'Access-Control-Allow-Methods': 'POST, OPTIONS' }
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } })
const safeCount = async (db: any, table: string, column = 'id') => { const { count, error } = await db.from(table).select(column, { count: 'exact', head: true }); return error ? null : count }
const cleanSearch = (value: unknown) => String(value ?? '').trim().replace(/[%_,]/g, '')
const limitOf = (value: unknown, max = 100) => Math.min(Math.max(Number(value ?? 50), 1), max)

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405)
  const authHeader = req.headers.get('Authorization')
  if (!authHeader?.startsWith('Bearer ')) return json({ error: 'Authentication required' }, 401)
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  const caller = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authHeader } } })
  const adminDb = createClient(supabaseUrl, serviceKey)
  const { data: { user }, error: userError } = await caller.auth.getUser()
  if (userError || !user) return json({ error: 'Invalid session' }, 401)
  const { data: adminUser, error: adminError } = await adminDb.schema('admin').from('admin_users').select('user_id, role_id, active, mfa_required').eq('user_id', user.id).eq('active', true).maybeSingle()
  if (adminError || !adminUser) return json({ error: 'Admin access denied' }, 403)
  const { data: role, error: roleError } = await adminDb.schema('admin').from('roles').select('key,name').eq('id', adminUser.role_id).single()
  if (roleError || !role) return json({ error: 'Admin role is invalid' }, 403)
  const { data: assurance } = await caller.auth.mfa.getAuthenticatorAssuranceLevel()
  if (adminUser.mfa_required && assurance?.currentLevel !== 'aal2') return json({ error: 'MFA required', code: 'MFA_REQUIRED' }, 403)
  const { data: rolePermissions, error: permissionError } = await adminDb.schema('admin').from('role_permissions').select('permission_id').eq('role_id', adminUser.role_id)
  if (permissionError) return json({ error: 'Permission resolution failed' }, 500)
  const ids = (rolePermissions ?? []).map((row: any) => row.permission_id)
  const { data: permissionRows } = ids.length ? await adminDb.schema('admin').from('permissions').select('key').in('id', ids) : { data: [] as any[] }
  const permissions = (permissionRows ?? []).map((row: any) => row.key).filter(Boolean)
  const requestId = req.headers.get('x-request-id') ?? crypto.randomUUID()
  const body = await req.json().catch(() => ({}))
  const action = body.action ?? 'me'
  const isSuper = role.key === 'super_admin'
  const allowed = (permission: string) => isSuper || permissions.includes(permission)
  const appendAudit = async (audit: any) => { await adminDb.schema('admin').from('audit_log').insert({ actor_user_id:user.id, actor_role:role.key, action:audit.action, target_schema:audit.target_schema ?? 'public', target_table:audit.target_table ?? null, target_id:audit.target_id ?? null, before_data:audit.before_data ?? null, after_data:audit.after_data ?? null, metadata:{ ...(audit.metadata ?? {}), source:'mela-central-dashboard' }, request_id:requestId }) }
  if (action === 'me') return json({ user:{id:user.id,email:user.email}, role, permissions, mfa:assurance })

  if (action === 'dashboard') {
    if (!allowed('dashboard.read') && !allowed('platform.read')) return json({ error:'Permission denied' },403)
    const specs = [['users','profiles'],['payments','payments'],['payouts','payout_requests'],['employer_registrations','employer_registration_requests'],['opportunities','opportunities'],['reports','reports'],['integrity_events','arena_integrity_events'],['feature_flags','platform_feature_flags']] as const
    const counts = await Promise.all(specs.map(async ([key,table]) => [key, await safeCount(adminDb,table)]))
    return json({ metrics:{table_counts:Object.fromEntries(counts)}, generated_at:new Date().toISOString() })
  }

  if (action === 'queues') {
    if (!allowed('dashboard.read') && !allowed('platform.read')) return json({ error:'Permission denied' },403)
    const queues: Record<string,unknown[]> = {}
    const load = async (key:string, table:string, statuses:string[]) => { const {data,error}=await adminDb.from(table).select('*').in('status',statuses).order('created_at',{ascending:false}).limit(50); queues[key]=error?[]:(data??[]) }
    await load('employer_registrations','employer_registration_requests',['pending','review','review_required'])
    await load('opportunities','opportunities',['pending','review','flagged'])
    await load('reports','reports',['pending','open','review','escalated'])
    await load('payouts','payout_requests',['pending','queued','failed','review'])
    const {data:attempts}=await adminDb.from('assessment_attempts').select('*').in('proctor_status',['pending','review','flagged']).order('started_at',{ascending:false}).limit(50); queues.proctor_reviews=attempts??[]
    const {data:integrity}=await adminDb.from('arena_integrity_events').select('*').gte('severity',2).order('created_at',{ascending:false}).limit(50); queues.arena_integrity=integrity??[]
    return json(queues)
  }

  if (action === 'users.list') {
    if (!allowed('users.read')) return json({error:'Permission denied'},403)
    const limit=limitOf(body.limit,100), offset=Math.max(Number(body.offset??0),0)
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
    const userId=String(body.user_id??''); const nextStatus=body.account_status===undefined?undefined:String(body.account_status); const statuses=['active','suspended','pending','restricted','deactivated']
    if(!userId)return json({error:'User ID is required'},400); if(nextStatus!==undefined&&!statuses.includes(nextStatus))return json({error:'Invalid account status'},400); if(userId===user.id&&nextStatus&&nextStatus!=='active')return json({error:'You cannot deactivate or suspend your current admin account here'},409)
    const {data:existing,error:readError}=await adminDb.from('profiles').select('id,account_status,email_verified,phone_verified').eq('id',userId).maybeSingle(); if(readError)return json({error:'Unable to read user'},500); if(!existing)return json({error:'User not found'},404)
    const patch:Record<string,unknown>={}; if(nextStatus!==undefined)patch.account_status=nextStatus; if(body.email_verified!==undefined)patch.email_verified=Boolean(body.email_verified); if(body.phone_verified!==undefined)patch.phone_verified=Boolean(body.phone_verified); if(!Object.keys(patch).length)return json({error:'No supported changes supplied'},400)
    const {data:updated,error:updateError}=await adminDb.from('profiles').update(patch).eq('id',userId).select('id,account_status,email_verified,phone_verified,updated_at').maybeSingle(); if(updateError)return json({error:'Unable to update user'},500); if(!updated)return json({error:'User changed concurrently; no update performed'},409)
    await appendAudit({action:'user.update',target_table:'profiles',target_id:userId,before_data:existing,after_data:updated,metadata:{changed_fields:Object.keys(patch)}}); return json({data:updated})
  }

  if (action === 'employers.list') {
    if (!allowed('employers.manage')) return json({error:'Permission denied'},403)
    const status=body.status; let q=adminDb.from('employer_registration_requests').select('*').order('created_at',{ascending:false}).limit(limitOf(body.limit,100)); if(status)q=q.eq('status',status); const {data,error}=await q; if(error)return json({error:'Unable to load employer registrations'},500); return json({data:data??[]})
  }
  if (action === 'employer.review') {
    if (!allowed('employers.manage')) return json({error:'Permission denied'},403)
    const id=String(body.request_id??''); const next=String(body.status??''); const notes=String(body.review_notes??'').trim(); if(!id||!['approved','rejected','pending','review'].includes(next))return json({error:'Request ID and valid status are required'},400)
    const {data:existing,error:r}=await adminDb.from('employer_registration_requests').select('*').eq('id',id).maybeSingle(); if(r)return json({error:'Unable to read employer request'},500); if(!existing)return json({error:'Employer request not found'},404)
    const {data:updated,error:u}=await adminDb.from('employer_registration_requests').update({status:next,review_notes:notes||null,reviewed_by:user.id,reviewed_at:new Date().toISOString(),updated_at:new Date().toISOString()}).eq('id',id).select('*').maybeSingle(); if(u)return json({error:'Unable to update employer request'},500); await appendAudit({action:'employer.review',target_table:'employer_registration_requests',target_id:id,before_data:existing,after_data:updated,metadata:{status:next}}); return json({data:updated})
  }

  if (action === 'opportunities.list') {
    if (!allowed('employers.manage')) return json({error:'Permission denied'},403)
    let q=adminDb.from('opportunities').select('id,title,organization_name,employer_id,status,moderation_status,verified_active,created_at,updated_at,deadline,reviewed_by,reviewed_at').order('created_at',{ascending:false}).limit(limitOf(body.limit,100)); if(body.status)q=q.eq('status',body.status); if(body.moderation_status)q=q.eq('moderation_status',body.moderation_status); const {data,error}=await q; if(error)return json({error:'Unable to load opportunities'},500); return json({data:data??[]})
  }
  if (action === 'opportunity.review') {
    if (!allowed('employers.manage')) return json({error:'Permission denied'},403)
    const id=String(body.opportunity_id??''); const status=String(body.moderation_status??''); const notes=String(body.moderation_notes??'').trim(); if(!id||!['approved','rejected','pending','flagged'].includes(status))return json({error:'Opportunity ID and valid moderation status are required'},400)
    const {data:existing,error:r}=await adminDb.from('opportunities').select('*').eq('id',id).maybeSingle(); if(r)return json({error:'Unable to read opportunity'},500); if(!existing)return json({error:'Opportunity not found'},404)
    const patch:any={moderation_status:status,moderation_notes:notes||null,reviewed_by:user.id,reviewed_at:new Date().toISOString(),updated_at:new Date().toISOString()}; if(status==='approved')patch.verified_active=true; if(status==='rejected')patch.verified_active=false
    const {data:updated,error:u}=await adminDb.from('opportunities').update(patch).eq('id',id).select('id,title,status,moderation_status,verified_active,moderation_notes,reviewed_by,reviewed_at,updated_at').maybeSingle(); if(u)return json({error:'Unable to review opportunity'},500); await appendAudit({action:'opportunity.review',target_table:'opportunities',target_id:id,before_data:existing,after_data:updated,metadata:{status}}); return json({data:updated})
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
    const [{data:reports},{data:integrity},{data:flaggedOpportunities}]=await Promise.all([adminDb.from('reports').select('*').in('status',['pending','open','review','escalated']).order('created_at',{ascending:false}).limit(50),adminDb.from('arena_integrity_events').select('*').gte('severity',2).order('created_at',{ascending:false}).limit(50),adminDb.from('opportunities').select('id,title,organization_name,status,moderation_status,moderation_notes,created_at').in('moderation_status',['flagged','pending','rejected']).order('created_at',{ascending:false}).limit(50)])
    return json({reports:reports??[],integrity_events:integrity??[],flagged_opportunities:flaggedOpportunities??[]})
  }
  if (action === 'report.resolve') {
    if (!allowed('moderation.manage')) return json({error:'Permission denied'},403)
    const id=String(body.report_id??''); const status=String(body.status??'resolved'); const notes=String(body.resolution_notes??'').trim(); if(!id||!['resolved','dismissed','escalated'].includes(status))return json({error:'Report ID and valid status are required'},400)
    const {data:existing,error:r}=await adminDb.from('reports').select('*').eq('id',id).maybeSingle(); if(r)return json({error:'Unable to read report'},500); if(!existing)return json({error:'Report not found'},404)
    const {data:updated,error:u}=await adminDb.from('reports').update({status,resolution_notes:notes||null,assigned_to:user.id,resolved_at:status==='resolved'||status==='dismissed'?new Date().toISOString():null}).eq('id',id).select('*').maybeSingle(); if(u)return json({error:'Unable to update report'},500); await appendAudit({action:'report.resolve',target_table:'reports',target_id:id,before_data:existing,after_data:updated,metadata:{status}}); return json({data:updated})
  }

  if (action === 'settings.flags') {
    if (!allowed('system.manage')) return json({error:'Permission denied'},403)
    const {data,error}=await adminDb.from('platform_feature_flags').select('*').order('feature_key'); if(error)return json({error:'Unable to load feature flags'},500); return json({data:data??[]})
  }
  if (action === 'settings.flag.update') {
    if (!allowed('system.manage')) return json({error:'Permission denied'},403)
    const featureKey=String(body.feature_key??''); if(!featureKey)return json({error:'Feature key is required'},400); const {data:existing,error:r}=await adminDb.from('platform_feature_flags').select('*').eq('feature_key',featureKey).maybeSingle(); if(r)return json({error:'Unable to read feature flag'},500); if(!existing)return json({error:'Feature flag not found'},404)
    const patch:any={}; if(body.enabled!==undefined)patch.enabled=Boolean(body.enabled); if(body.maintenance_message!==undefined)patch.maintenance_message=String(body.maintenance_message); if(body.config!==undefined)patch.config=body.config; patch.updated_by=user.id; patch.updated_at=new Date().toISOString(); const {data:updated,error:u}=await adminDb.from('platform_feature_flags').update(patch).eq('feature_key',featureKey).select('*').maybeSingle(); if(u)return json({error:'Unable to update feature flag'},500); await appendAudit({action:'settings.flag.update',target_table:'platform_feature_flags',target_id:featureKey,before_data:existing,after_data:updated,metadata:{changed_fields:Object.keys(patch)}}); return json({data:updated})
  }

  if (action === 'commission.list') {
    if (!allowed('finance.manage')) return json({error:'Permission denied'},403); const limit=limitOf(body.limit,200); let q=adminDb.from('invitation_commissions').select('*').order('created_at',{ascending:false}).limit(limit); if(body.status)q=q.eq('status',body.status); const search=cleanSearch(body.search); if(search)q=q.or(`invitation_code.ilike.%${search}%,transaction_reference.ilike.%${search}%`); const {data,error}=await q; if(error)return json({error:error.message},500); return json({data:data??[]})
  }
  if (action === 'commission.inspect') {
    if (!allowed('finance.manage')) return json({error:'Permission denied'},403); const id=String(body.commission_id??''); if(!id)return json({error:'Commission ID is required'},400); const {data,error}=await adminDb.from('invitation_commissions').select('*').eq('id',id).maybeSingle(); if(error)return json({error:error.message},500); if(!data)return json({error:'Commission not found'},404); return json({data})
  }
  if (action === 'commission.cancel') {
    if (!allowed('finance.manage')) return json({error:'Permission denied'},403); const id=String(body.commission_id??''); const reason=String(body.reason??'').trim(); if(!id||!reason)return json({error:'Commission ID and cancellation reason are required'},400); if(reason.length>500)return json({error:'Cancellation reason must be 500 characters or fewer'},400); const {data:existing,error:r}=await adminDb.from('invitation_commissions').select('*').eq('id',id).maybeSingle(); if(r)return json({error:r.message},500); if(!existing)return json({error:'Commission not found'},404); if(existing.status==='cancelled')return json({data:existing,already_cancelled:true}); if(existing.status==='paid')return json({error:'Paid commissions require a separate reversal workflow'},409); const {data:updated,error:u}=await adminDb.from('invitation_commissions').update({status:'cancelled',cancelled_at:new Date().toISOString(),cancellation_reason:reason}).eq('id',id).eq('status','pending').select('*').maybeSingle(); if(u)return json({error:u.message},500); if(!updated)return json({error:'Commission changed concurrently; no cancellation performed'},409); await appendAudit({action:'commission.cancel',target_table:'invitation_commissions',target_id:id,before_data:existing,after_data:updated,metadata:{reason}}); return json({data:updated})
  }

  if (action === 'authorization.matrix') {
    if (!allowed('authorization.manage')) return json({error:'Permission denied'},403); const [{data:roles,error:re},{data:allPermissions,error:pe},{data:mappings,error:me}]=await Promise.all([adminDb.schema('admin').from('roles').select('id,key,name,description,is_privileged').order('name'),adminDb.schema('admin').from('permissions').select('id,key,name,description').order('key'),adminDb.schema('admin').from('role_permissions').select('role_id,permission_id')]); if(re||pe||me)return json({error:'Authorization matrix unavailable'},500); return json({roles,permissions:allPermissions,mappings})
  }
  if (action === 'audit.list') { if(!allowed('audit.read'))return json({error:'Permission denied'},403); const {data,error}=await adminDb.schema('admin').from('audit_log').select('*').order('created_at',{ascending:false}).limit(limitOf(body.limit,200)); if(error)return json({error:error.message},500); return json({data:data??[]}) }
  if (action === 'access.list') { if(!allowed('authorization.manage'))return json({error:'Permission denied'},403); const {data,error}=await adminDb.schema('admin').from('access_requests').select('*').order('created_at',{ascending:false}).limit(100); if(error)return json({error:error.message},500); return json({data:data??[]}) }
  if (action === 'audit.append') { if(!allowed('authorization.manage'))return json({error:'Permission denied'},403); const audit=body.audit??{}; const {error}=await adminDb.schema('admin').from('audit_log').insert({actor_user_id:user.id,actor_role:role.key,action:audit.action??'admin.action',target_schema:audit.target_schema??null,target_table:audit.target_table??null,target_id:audit.target_id??null,before_data:audit.before_data??null,after_data:audit.after_data??null,metadata:{...(audit.metadata??{}),source:'mela-central-dashboard'},request_id:requestId}); if(error)return json({error:error.message},500); return json({ok:true}) }
  return json({error:'Unknown admin action'},400)
})
