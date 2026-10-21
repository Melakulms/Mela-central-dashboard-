import { createClient } from '@supabase/supabase-js'

const STAGING='https://tungqfmypuwzeyrtaseh.supabase.co'
if(process.env.SUPABASE_URL!==STAGING) throw new Error('Refusing non-staging target')
const publishable=process.env.SUPABASE_PUBLISHABLE_KEY
if(!publishable?.startsWith('sb_publishable_')) throw new Error('Staging publishable key unavailable')
const c=createClient(STAGING,publishable,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}})
const tests=[
  ['anonymous_grant',()=>c.rpc('admin_learning_access_v1',{p_action:'admin_grant',p_data:{learner_user_id:'00000000-0000-0000-0000-000000000001',product_key:'practice_plus_30d',reason:'Anonymous users must never grant scholarships'}})],
  ['anonymous_revoke',()=>c.rpc('admin_learning_access_v1',{p_action:'admin_revoke',p_data:{learner_user_id:'00000000-0000-0000-0000-000000000001',product_key:'practice_plus_30d',reason:'Anonymous users must never revoke scholarships'}})],
  ['anonymous_history',()=>c.rpc('admin_learning_grant_query_v1',{p_search:'test',p_learner:null})],
  ['anonymous_test_setup',()=>c.rpc('staging_scholarship_test_setup_v1',{p_reviewer:'00000000-0000-0000-0000-000000000001',p_learner:'00000000-0000-0000-0000-000000000002',p_other:'00000000-0000-0000-0000-000000000003'})],
  ['anonymous_test_cleanup',()=>c.rpc('staging_scholarship_test_cleanup_v1',{p_ids:['00000000-0000-0000-0000-000000000001']})],
]
for(const [name,call] of tests){
 const {error,data}=await call()
 if(!error)throw new Error(name+' was allowed unexpectedly; response type '+typeof data)
 if(!/permission|MFA required|not allowed|unauthorized|not granted/i.test(error.message)) throw new Error(name+' failed for unexpected reason: '+error.message.slice(0,180))
 console.log('LIVE_STAGING_HTTP_PASS '+name+': '+error.message.slice(0,180))
}
const anonWrite=await c.from('mela_user_learning_entitlements').insert({
 user_id:'00000000-0000-0000-0000-000000000001',
 product_key:'practice_plus_30d',source:'admin',source_reference:'ANON-SHOULD-NOT-APPEAR',status:'active'
}).select('id')
if(!anonWrite.error)throw new Error('Anonymous direct entitlement insert was allowed')
console.log('LIVE_STAGING_HTTP_PASS anonymous_direct_insert: '+anonWrite.error.message.slice(0,180))
console.log('LIVE_STAGING_HTTP_PASS total=6, no login or test rows required')
