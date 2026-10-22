/**
 * Staging-only administrative provisioning does not send registration email.
 * STAGING ONLY real Supabase Auth/MFA scholarship integration tests.
 * Credentials and TOTP seed exist solely in this test process memory.
 * No secrets, sessions, codes, receipt data or password hashes are printed.
 * User cleanup is performed by the staging database owner after the run.
 */
import { createClient } from '@supabase/supabase-js'
import { createHmac, randomBytes, randomUUID } from 'node:crypto'

const PROJECT = 'tungqfmypuwzeyrtaseh'
const URL = 'https://' + PROJECT + '.supabase.co'
if (process.env.SUPABASE_URL !== URL) throw new Error('Refusing to run against a non-staging Supabase URL')
const KEY = process.env.SUPABASE_PUBLISHABLE_KEY
if (!KEY?.startsWith('sb_publishable_')) throw new Error('Staging publishable key missing')
const SERVICE_KEY = process.env.STAGING_SUPABASE_SERVICE_ROLE_KEY
if (!SERVICE_KEY) throw new Error('Secure staging service-role key unavailable in GitHub Actions secrets; no test users created')
const admin = createClient(URL, SERVICE_KEY, {auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}})
const marker = String(process.env.GITHUB_RUN_ID || Date.now())
const refs = []
const clients = []
const results = []
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms))
function client() {
 const c = createClient(URL, KEY, {auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}})
 clients.push(c)
 return c
}
function output(key, status, detail) {
 const record = {test:key,status,detail}
 results.push(record)
 console.log('RESULT ' + JSON.stringify(record))
}
function cleanError(e) {
 const x = e?.message ?? String(e)
 if (x.includes('Payment reviewer permission and MFA required')) return '42501: Payment reviewer permission and MFA required'
 return x.slice(0,220).replace(/(Bearer|JWT|TOTP|password|secret|token)\s+\S+/ig,'[redacted]')
}
function check(result, where) {
 if (result.error) throw new Error(where + ': ' + cleanError(result.error))
 return result.data
}
function expectRefusal(res, label) {
 if (!res.error) throw new Error(label + ': operation incorrectly permitted')
 if (!/Payment reviewer permission and MFA required/i.test(res.error.message)) throw new Error(label + ': wrong refusal ' + cleanError(res.error))
}
async function createAccount(name) {
 const c = client()
 const email = 'mela-' + name + '-' + marker + '-' + randomBytes(16).toString('hex') + '@gmail.com'
 const password = randomBytes(32).toString('base64url') + 'Z9!'
 const {data,error} = await admin.auth.admin.createUser({email,password,email_confirm:true,user_metadata:{test_account:true,role:'student',full_name:'Test ' + name},app_metadata:{mela_staging_test_account:true}})
 if (error || !data.user) throw new Error('Auth signup for '+name+': '+cleanError(error || 'no user returned'))
 refs.push({role:name,id:data.user.id,email,password,client:c})
 console.log('ACCOUNT_CREATED ' + JSON.stringify({name,id:data.user.id,email}))
 return refs[refs.length-1]
}
async function signIn(account) {
 for (let i=0;i<5;i++) {
  const {error} = await account.client.auth.signInWithPassword({email:account.email,password:account.password})
  if (!error) return
  if (i===4) throw new Error('Auth sign-in not available after approval for '+account.role+': '+cleanError(error))
  await sleep(1000)
 }
}
function base32Decode(input) {
 const alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'
 let buffer=0, bits=0;const out=[]
 for(const ch of input.toUpperCase().replace(/[^A-Z2-7]/g,'')) {
  const idx=alphabet.indexOf(ch)
  if(idx<0)continue
  buffer=(buffer<<5)|idx;bits+=5
  if(bits>=8){bits-=8;out.push((buffer>>bits)&255)}
 }
 return Buffer.from(out)
}
function totp(seed, offset=0) {
 const count=Math.floor(Date.now()/30000)+offset
 const bytes=Buffer.alloc(8);bytes.writeBigUInt64BE(BigInt(count))
 const digest=createHmac('sha1',base32Decode(seed)).update(bytes).digest()
 const position=digest[digest.length-1]&15
 return String((digest.readUInt32BE(position)&0x7fffffff)%1_000_000).padStart(6,'0')
}
async function enrollActualMfa(account) {
 const auth=account.client.auth
 const enrollment=check(await auth.mfa.enroll({factorType:'totp',friendlyName:'MELA STAGING E2E'}),'MFA enrollment')
 if(!enrollment?.id || !enrollment.totp?.secret) throw new Error('No enrollment factor returned')
 const seed=enrollment.totp.secret // memory only
 for(const offset of [0,-1,1]) {
   const challenge=check(await auth.mfa.challenge({factorId:enrollment.id}),'MFA challenge')
   const {error}=await auth.mfa.verify({factorId:enrollment.id,challengeId:challenge.id,code:totp(seed,offset)})
   if(!error) {
     const aal=check(await auth.mfa.getAuthenticatorAssuranceLevel(),'MFA assurance')
     if(aal.currentLevel!=='aal2')throw new Error('Verified factor did not produce aal2')
     output('real_mfa_sign_in','PASS','Auth challenge and TOTP verification yielded aal2')
     return enrollment.id
   }
 }
 throw new Error('Actual MFA authenticator verification was unsuccessful')
}
async function invoke(c,action,learnerId,productKey,reason,endsAt=null) {
 return c.rpc('admin_learning_access_v1',{p_action:action,p_data:{learner_user_id:learnerId,product_key:productKey,reason,ends_at:endsAt}})
}
const waitForReviewer=async account=>{
 for(let i=0;i<90;i++){
   const res=await account.client.rpc('admin_learning_grant_query_v1',{p_search:'',p_learner:null})
   if(!res.error)return
   if(!/Payment reviewer permission and MFA required/i.test(res.error.message))throw new Error('Reviewer query unexpected error: '+cleanError(res.error))
   await sleep(2000)
 }
 throw new Error('Real aal2 session never became an active payment reviewer')
}
try {
 const reviewer=await createAccount('reviewer')
 const learner=await createAccount('learner')
 const other=await createAccount('other-learner')
 console.log('TEST_ACCOUNT_CREATION_COMPLETE ' + refs.length)
 check(await admin.rpc('staging_scholarship_test_setup_v1',{
   p_reviewer:reviewer.id,p_learner:learner.id,p_other:other.id
 }), 'staging service-role test account setup')
 console.log('TEST_STAGING_SETUP_COMPLETE reviewer assigned and three test profiles active')
 await Promise.all(refs.map(signIn))
 const initial=await invoke(learner.client,'admin_grant',learner.id,'practice_plus_30d','Non-reviewer must be denied')
 expectRefusal(initial,'non-reviewer grant')
 const withoutMfa=await invoke(reviewer.client,'admin_grant',learner.id,'practice_plus_30d','Reviewer without MFA denied')
 expectRefusal(withoutMfa,'reviewer without MFA grant')
 const withoutMfaRevoke=await invoke(reviewer.client,'admin_revoke',learner.id,'practice_plus_30d','Reviewer without MFA revoke')
 expectRefusal(withoutMfaRevoke,'reviewer without MFA revoke')
 output('a','PASS','Non-reviewer and aal1 reviewer both refused grant; aal1 reviewer refused revoke')
 const factorId=await enrollActualMfa(reviewer)
 await waitForReviewer(reviewer)
 const product='practice_plus_30d'
 const first=check(await invoke(reviewer.client,'admin_grant',learner.id,product,'Student scholarship awarded in staging e2e test'),'first grant')
 if(first.source!=='admin'||first.existing!==false)throw new Error('First grant invalid source/existing')
 const own=check(await learner.client.from('mela_user_learning_entitlements').select('id,product_key,source,status').eq('id',first.grant_id),'learner own entitlement')
 if(own.length!==1 || own[0].source!=='admin' || own[0].status!=='active')throw new Error('Learner entitlement missing')
 output('b','PASS','Active eligible scholarship grant visible to owner with source=admin')
 const second=check(await invoke(reviewer.client,'admin_grant',learner.id,product,'Repeat scholarship request must be idempotent'),'duplicate grant')
 if(second.grant_id!==first.grant_id||second.existing!==true)throw new Error('Duplicate grant created a new row')
 output('c','PASS','Repeat grant returns identical grant ID, existing=true')
 const invalid=[
  ['inactive_product',await invoke(reviewer.client,'admin_grant',learner.id,'ai_career_academy','Inactive product must be rejected')],
  ['unknown_user',await invoke(reviewer.client,'admin_grant','00000000-0000-0000-0000-000000000001',product,'Unknown learner must be rejected')],
  ['short_reason',await invoke(reviewer.client,'admin_grant',learner.id,'grade12_exam_master','tiny')],
  ['institution',await invoke(reviewer.client,'admin_grant',learner.id,'institution_learning_license','Institution must never be granted')]
 ]
 for(const [name,x] of invalid){if(!x.error)throw new Error(name+' was accepted')}
 output('d','PASS','Inactive, unknown user, short reason and institutional licence rejected')
 const another=check(await other.client.from('mela_user_learning_entitlements').select('id').eq('id',first.grant_id),'cross-student read')
 if(another.length!==0)throw new Error('Learner could read another learner grant')
 for(const [action,result] of [
  ['insert',await other.client.from('mela_user_learning_entitlements').insert({user_id:other.id,product_key:product,status:'active',source:'admin',source_reference:'malicious-test'})],
  ['update',await learner.client.from('mela_user_learning_entitlements').update({status:'revoked'}).eq('id',first.grant_id).select('id')],
  ['delete',await learner.client.from('mela_user_learning_entitlements').delete().eq('id',first.grant_id).select('id')]
 ]) {if(!result.error && ((Array.isArray(result.data)&&result.data.length>0) || (result.count ?? 0)>0))throw new Error('Learner ' + action + ' succeeded unexpectedly')}
 const stillOwned=check(await learner.client.from('mela_user_learning_entitlements').select('id,status').eq('id',first.grant_id),'read after direct DML attempts')
 if(stillOwned.length!==1||stillOwned[0].status!=='active') throw new Error('Learner DML changed or deleted their own grant')
 output('e','PASS','Cross-learner read returns zero rows; insert/update/delete denied')
 const concurrent=await Promise.all([
   invoke(reviewer.client,'admin_grant',learner.id,'grade12_exam_master','First concurrent scholarship grant'),
   invoke(reviewer.client,'admin_grant',learner.id,'grade12_exam_master','Second concurrent scholarship grant'),
 ])
 const c1=check(concurrent[0],'concurrent grant A'),c2=check(concurrent[1],'concurrent grant B')
 if(c1.grant_id!==c2.grant_id || c1.existing===c2.existing)throw new Error('Concurrency idempotency failed')
 const active=check(await learner.client.from('mela_user_learning_entitlements').select('id').eq('user_id',learner.id).eq('product_key','grade12_exam_master').eq('source','admin').eq('status','active'),'active count')
 if(active.length!==1)throw new Error('Two active rows were created')
 output('f','PASS','Two real parallel RPC requests generated exactly one active grant')
 const revoked=check(await invoke(reviewer.client,'admin_revoke',learner.id,product,'End scholarship after staging review'),'revoke grant')
 if(revoked.status!=='revoked')throw new Error('Revoke returned wrong status')
 const rows=check(await learner.client.from('mela_user_learning_entitlements').select('id,status,ends_at').eq('id',first.grant_id),'revoke persistence')
 if(rows.length!==1||rows[0].status!=='revoked'||!rows[0].ends_at)throw new Error('Revoke deleted row or lacked end timestamp')
 const aud=check(await reviewer.client.rpc('admin_learning_grant_query_v1',{p_search:'',p_learner:learner.id}),'audit query')
 if(!aud.audit?.some(row=>row.action==='revoked'&&row.grant_id===first.grant_id))throw new Error('Revocation audit event missing')
 output('g','PASS','Revoke keeps row and writes required audit event')
 console.log('ALL_REAL_AUTH_TESTS_COMPLETE '+JSON.stringify({passed:results.filter(r=>r.status==='PASS').length,accountCount:refs.length,factorCount:1}))
} catch(err) {
 output('run','FAIL',cleanError(err))
 process.exitCode=1
} finally {
 for(const item of refs){try{await item.client.auth.signOut({scope:'global'})}catch{}}
 if (refs.length) {
   const ids=refs.map(x=>x.id)
   const prep=await admin.rpc('staging_scholarship_test_cleanup_v1',{p_ids:ids})
   if(prep.error) output('cleanup_preparation','FAIL',cleanError(prep.error))
   else output('cleanup_preparation','PASS','Only tagged staging scholarship grants, reviewer rows and audit rows removed')
   let failed=0
   for(const item of refs){
     const del=await admin.auth.admin.deleteUser(item.id)
     if(del.error){failed++;console.log('CLEANUP_USER_FAILED '+JSON.stringify({role:item.role,error:cleanError(del.error)}))}
   }
   output('cleanup_auth',failed?'FAIL':'PASS',failed?String(failed)+' staging Auth users could not be deleted':'All staging Auth test users and their Auth MFA data deleted via Auth Admin API')
 } else output('cleanup','PASS','No test accounts were created')
}
