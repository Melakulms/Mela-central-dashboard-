import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const cors={
  'Access-Control-Allow-Origin':'*',
  'Access-Control-Allow-Headers':'authorization, apikey, content-type',
  'Access-Control-Allow-Methods':'POST, OPTIONS',
  'Content-Type':'application/json',
  'Cache-Control':'no-store'
};
function json(d:unknown,s=200){return new Response(JSON.stringify(d),{status:s,headers:cors})}
async function authenticatedUser(req:Request){
 const token=req.headers.get('Authorization');if(!token?.startsWith('Bearer '))throw Object.assign(new Error('Authentication required'),{status:401});
 const r=await fetch(`${Deno.env.get('SUPABASE_URL')}/auth/v1/user`,{headers:{apikey:Deno.env.get('SUPABASE_ANON_KEY')!,Authorization:token}});
 if(!r.ok)throw Object.assign(new Error('Invalid session'),{status:401});const user=await r.json();if(!user.id)throw Object.assign(new Error('Invalid session'),{status:401});return user.id as string;
}
async function rest(path:string,init:RequestInit={}){
  const u=Deno.env.get('SUPABASE_URL')!,k=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const h=new Headers(init.headers||{});h.set('apikey',k);h.set('Authorization',`Bearer ${k}`);if(init.body)h.set('Content-Type','application/json');
  const r=await fetch(`${u}/rest/v1/${path}`,{...init,headers:h});const tx=await r.text();let d:any=null;try{d=tx?JSON.parse(tx):null}catch{d=tx}
  if(!r.ok)throw Object.assign(new Error(typeof d==='object'?(d?.message||d?.hint||`Database error ${r.status}`):`Database error ${r.status}`),{status:r.status});return d
}
async function patch(table:string,filter:string,body:any){return rest(`${table}?${filter}`,{method:'PATCH',headers:{Prefer:'return=minimal'},body:JSON.stringify(body)})}
async function featureAvailable(key:string){return (await rest('rpc/platform_feature_available',{method:'POST',body:JSON.stringify({p_feature_key:key})}))===true}
async function notify(user_id:string,title:string,body:string,ref_table?:string,ref_id?:string){try{await rest('notifications',{method:'POST',headers:{Prefer:'return=minimal'},body:JSON.stringify({user_id,title,body,ref_table:ref_table||null,ref_id:ref_id||null})})}catch(e){console.error('notify',e)}}
function paymentMode(){return Deno.env.get('MELA_PAYMENT_MODE')==='live'?'live':'test'}
function chapaKey(){const key=Deno.env.get('CHAPA_SECRET_KEY');if(!key)throw Object.assign(new Error('Chapa secret key is not configured.'),{status:503,code:'CHAPA_NOT_CONFIGURED'});const mode=paymentMode();if(mode==='test'&&!/TEST/i.test(key))throw Object.assign(new Error('Test mode requires a Chapa TEST secret key.'),{status:503,code:'CHAPA_TEST_KEY_REQUIRED'});if(mode==='live'&&/TEST/i.test(key))throw Object.assign(new Error('Live mode requires a Chapa live secret key.'),{status:503,code:'CHAPA_LIVE_KEY_REQUIRED'});return key}
async function hasEmployerAccess(uid:string,employerId:string){const e=await rest(`employers?id=eq.${employerId}&select=owner_id&limit=1`);if(e?.[0]?.owner_id===uid)return true;const m=await rest(`employer_members?employer_id=eq.${employerId}&user_id=eq.${uid}&status=eq.active&member_role=in.(admin,hiring_manager,recruiter)&select=id&limit=1`);return !!m?.length}
async function getEscrowContext(escrowId:string){
  const es=(await rest(`escrow_transactions?id=eq.${escrowId}&select=id,status,amount_minor,currency,contract_id,task_id,user_id,funded_at,transaction_type&limit=1`))?.[0];
  if(!es)throw Object.assign(new Error('Escrow not found'),{status:404});
  const c=(await rest(`freelance_contracts?id=eq.${es.contract_id}&select=id,employer_id,freelancer_id,task_id,status,funding_status,agreed_amount&limit=1`))?.[0];
  if(!c)throw Object.assign(new Error('Contract not found'),{status:404});return {es,c}
}
async function verifyFundingAttempt(p:any){
  const key=chapaKey();const r=await fetch(`https://api.chapa.co/v1/transaction/verify/${encodeURIComponent(p.tx_ref)}`,{headers:{Authorization:`Bearer ${key}`}});
  const tx=await r.text();let b:any={};try{b=tx?JSON.parse(tx):{}}catch{}const now=new Date().toISOString();
  if(!r.ok){await patch('escrow_payment_attempts',`id=eq.${p.id}`,{status:r.status===404?'pending':p.status,provider_status:b?.status||'pending',failure_reason:b?.message||`Chapa verify HTTP ${r.status}`,last_verified_at:now});return {state:r.status===404?'pending':'error',provider:b}}
  const d=b?.data||{},ps=String(d.status||'').toLowerCase();
  if(ps!=='success'){const mapped=ps==='failed'?'failed':'pending';await patch('escrow_payment_attempts',`id=eq.${p.id}`,{status:mapped,provider_status:ps||mapped,verify_payload:b,failure_reason:mapped==='failed'?(b?.message||'Payment failed'):null,last_verified_at:now});return {state:mapped,provider:b}}
  const minor=Math.round(Number(d.amount)*100);const checks:any={mode:String(d.mode||'').toLowerCase()===String(p.mode||'').toLowerCase(),tx_ref:String(d.tx_ref||'')===p.tx_ref,amount:Number.isFinite(minor)&&minor===Number(p.expected_amount_minor),currency:String(d.currency||'').toUpperCase()===String(p.currency||'').toUpperCase()};
  
  if(!Object.values(checks).every(Boolean)){await patch('escrow_payment_attempts',`id=eq.${p.id}`,{status:'failed',provider_status:ps,verify_payload:b,failure_reason:`Verification mismatch: ${JSON.stringify(checks)}`,last_verified_at:now});return {state:'mismatch',checks}}
  const out=await rest('rpc/finalize_escrow_payment',{method:'POST',body:JSON.stringify({p_payment_id:p.id,p_provider_ref:d.reference||d.ref_id||null,p_provider_method:d.method||null,p_provider_type:d.type||null,p_provider_charge:minor,p_verify_payload:b})});
  return {state:'success',result:out}
}
async function fundEscrow(uid:string,body:any){
  const escrowId=String(body?.escrow_id||'');if(!escrowId)throw Object.assign(new Error('escrow_id is required'),{status:400});const {es,c}=await getEscrowContext(escrowId);
  if(es.transaction_type!=='funding')throw Object.assign(new Error('Use the contract funding escrow transaction'),{status:409});
  if(!(await hasEmployerAccess(uid,c.employer_id)))throw Object.assign(new Error('Not authorized for this employer'),{status:403});
  if(es.status==='held')return {already_funded:true,escrow_id:es.id,status:'held'};if(!['funding_pending','failed'].includes(es.status))throw Object.assign(new Error(`Escrow cannot be funded from status ${es.status}`),{status:409});
  if(!es.amount_minor||Number(es.amount_minor)<=0)throw Object.assign(new Error('Escrow amount is invalid'),{status:400});
  const since=new Date(Date.now()-5*60*1000).toISOString();const attempts=await rest(`escrow_payment_attempts?escrow_id=eq.${es.id}&payer_id=eq.${uid}&status=in.(initiated,pending)&created_at=gte.${encodeURIComponent(since)}&select=id&limit=3`);if((attempts?.length||0)>=3)throw Object.assign(new Error('Too many recent funding attempts. Verify an existing checkout first.'),{status:429});
  const profile=(await rest(`profiles?id=eq.${uid}&select=full_name,email&limit=1`))?.[0];if(!profile?.email)throw Object.assign(new Error('Payer profile needs an email address'),{status:400});const parts=String(profile.full_name||'Mela Employer').trim().split(/\s+/);const first=parts[0]||'Mela',last=parts.slice(1).join(' ')||'Employer';
  const txRef=`mela_escrow_${paymentMode()}_${Date.now()}_${crypto.randomUUID().replaceAll('-','').slice(0,12)}`;const amount=(Number(es.amount_minor)/100).toFixed(2);const supabaseUrl=Deno.env.get('SUPABASE_URL')!;const callbackUrl=`${supabaseUrl}/functions/v1/mela-finance-callback`;const returnBase=(Deno.env.get('MELA_RETURN_URL')||`${supabaseUrl}/functions/v1/mela-web`).replace(/\/$/,'');const returnUrl=`${returnBase}?escrow=return&tx_ref=${encodeURIComponent(txRef)}`;
  const inserted=await rest('escrow_payment_attempts',{method:'POST',headers:{Prefer:'return=representation'},body:JSON.stringify({escrow_id:es.id,payer_id:uid,mode:paymentMode(),tx_ref:txRef,expected_amount_minor:es.amount_minor,currency:es.currency,status:'initiated'})});const attempt=inserted?.[0];const key=chapaKey();
  const cr=await fetch('https://api.chapa.co/v1/transaction/initialize',{method:'POST',headers:{Authorization:`Bearer ${key}`,'Content-Type':'application/json'},body:JSON.stringify({amount,currency:es.currency,email:profile.email,first_name:first,last_name:last,tx_ref:txRef,callback_url:callbackUrl,return_url:returnUrl,customization:{title:'Mela Escrow Funding',description:'Fund protected freelance contract escrow'},meta:{payment_reason:'Mela freelance escrow funding',escrow_id:es.id,contract_id:c.id}})});
  const txt=await cr.text();let ch:any={};try{ch=txt?JSON.parse(txt):{}}catch{}const checkout=ch?.data?.checkout_url;if(!cr.ok||!checkout){await patch('escrow_payment_attempts',`id=eq.${attempt.id}`,{status:'failed',failure_reason:ch?.message||`Chapa initialize failed (${cr.status})`});throw Object.assign(new Error(ch?.message||'Unable to initialize Chapa checkout'),{status:502})}
  await patch('escrow_payment_attempts',`id=eq.${attempt.id}`,{status:'pending',checkout_url:checkout,provider_status:ch?.status||'success'});return {checkout_url:checkout,tx_ref:txRef,mode:paymentMode(),escrow_id:es.id,amount,currency:es.currency}
}
async function verifyEscrow(uid:string,body:any){const ref=String(body?.tx_ref||'');if(!ref)throw Object.assign(new Error('tx_ref is required'),{status:400});const p=(await rest(`escrow_payment_attempts?tx_ref=eq.${encodeURIComponent(ref)}&select=*&limit=1`))?.[0];if(!p)throw Object.assign(new Error('Funding attempt not found'),{status:404});const {c}=await getEscrowContext(p.escrow_id);if(p.payer_id!==uid&&!(await hasEmployerAccess(uid,c.employer_id)))throw Object.assign(new Error('Not authorized'),{status:403});if(p.status==='success')return {status:'success',tx_ref:p.tx_ref,already_verified:true};if(!['initiated','pending'].includes(p.status))return {status:p.status,tx_ref:p.tx_ref};const result=await verifyFundingAttempt(p);return {status:result.state,tx_ref:p.tx_ref,checks:result.checks}}
async function listBanks(){const key=chapaKey();const r=await fetch('https://api.chapa.co/v1/banks',{headers:{Authorization:`Bearer ${key}`}});const tx=await r.text();let b:any={};try{b=tx?JSON.parse(tx):{}}catch{}if(!r.ok)throw Object.assign(new Error(b?.message||'Unable to load banks'),{status:r.status});return b}
async function finalizePayout(pr:any,externalRef?:string){const now=new Date().toISOString();await rest('rpc/record_milestone_payout',{method:'POST',body:JSON.stringify({p_milestone_id:pr.milestone_id,p_provider:'chapa',p_external_ref:externalRef||pr.provider_ref||pr.payout_ref})});await patch('payout_requests',`id=eq.${pr.id}`,{status:'success',provider_ref:externalRef||pr.provider_ref||null,completed_at:now,updated_at:now,failure_reason:null})}
async function verifyPayoutRow(pr:any){
  const key=chapaKey();const r=await fetch(`https://api.chapa.co/v1/transfers/verify/${encodeURIComponent(pr.payout_ref)}`,{headers:{Authorization:`Bearer ${key}`}});const tx=await r.text();let b:any={};try{b=tx?JSON.parse(tx):{}}catch{}
  if(!r.ok){await patch('payout_requests',`id=eq.${pr.id}&status=eq.queued`,{failure_reason:b?.message||`Transfer verification unavailable (${r.status})`,provider_payload:b});return {state:'queued'}}
  const st=String(b?.data?.status||'').toLowerCase();
  if(st==='success'){const details=b.data;const amount=Math.round(Number(details.amount)*100);if(String(details.reference||'')!==pr.payout_ref||!Number.isSafeInteger(amount)||amount!==Number(pr.amount_minor)||String(details.currency||'').toUpperCase()!==pr.currency){await patch('payout_requests',`id=eq.${pr.id}&status=eq.queued`,{failure_reason:'Transfer verification mismatch; manual reconciliation required',provider_payload:b});return {state:'queued'}}const ref=b?.data?.chapa_reference||b?.data?.reference||null;await patch('payout_requests',`id=eq.${pr.id}`,{provider_ref:ref,provider_payload:b,failure_reason:null});await finalizePayout(pr,ref||pr.payout_ref);return {state:'success',provider:b}}
  if(st.includes('fail')||st.includes('cancel')){await patch('payout_requests',`id=eq.${pr.id}&status=eq.queued`,{status:'failed',provider_payload:b,failure_reason:b?.message||st});return {state:'failed',provider:b}}
  await patch('payout_requests',`id=eq.${pr.id}&status=eq.queued`,{provider_payload:b});return {state:'queued',provider:b}
}
async function payout(uid:string,body:any){
  const milestoneId=String(body?.milestone_id||'');if(!milestoneId)throw Object.assign(new Error('milestone_id is required'),{status:400});
  const m=(await rest(`task_milestones?id=eq.${milestoneId}&select=id,contract_id,status&limit=1`))?.[0];if(!m)throw Object.assign(new Error('Milestone not found'),{status:404});if(!['approved','paid'].includes(m.status))throw Object.assign(new Error('Milestone must be approved before payout'),{status:409});
  const c=(await rest(`freelance_contracts?id=eq.${m.contract_id}&select=id,employer_id,freelancer_id&limit=1`))?.[0];if(!c||!(await hasEmployerAccess(uid,c.employer_id)))throw Object.assign(new Error('Not authorized'),{status:403});
  let pr=(await rest(`payout_requests?milestone_id=eq.${milestoneId}&status=in.(pending,queued,failed,success)&select=*&order=created_at.desc&limit=1`))?.[0];if(!pr)throw Object.assign(new Error('Payout request not found'),{status:404});if(pr.status==='success'||m.status==='paid')return {status:'success',already_paid:true,payout_ref:pr.payout_ref};
  if(body?.action==='verify'||pr.status==='queued'||pr.status==='failed'){const vr=await verifyPayoutRow(pr);return {status:vr.state,payout_ref:pr.payout_ref}}
  const account=(await rest(`payout_accounts?user_id=eq.${c.freelancer_id}&active=eq.true&select=*&limit=1`))?.[0];if(!account)throw Object.assign(new Error('Freelancer must configure an active payout account'),{status:409});
  if(pr.status!=='pending')throw Object.assign(new Error('Payout is not available for initiation'),{status:409});
  const key=chapaKey();const claimed=await rest('rpc/claim_mela_payout',{method:'POST',body:JSON.stringify({p_payout_id:pr.id,p_actor:uid})});if(!claimed)return {status:'queued',already_claimed:true,payout_ref:pr.payout_ref};pr=claimed;
  const payload:any={account_name:account.account_name,account_number:account.account_number,amount:(Number(pr.amount_minor)/100).toFixed(2),currency:'ETB',reference:pr.payout_ref,bank_code:account.bank_code};if(paymentMode()==='test')payload.status='success';
  const r=await fetch('https://api.chapa.co/v1/transfers',{method:'POST',headers:{Authorization:`Bearer ${key}`,'Content-Type':'application/json'},body:JSON.stringify(payload)});const tx=await r.text();let b:any={};try{b=tx?JSON.parse(tx):{}}catch{}
  if(!r.ok){await patch('payout_requests',`id=eq.${pr.id}`,{failure_reason:b?.message||`Transfer response uncertain (${r.status}); verify before any retry`,provider_payload:b});throw Object.assign(new Error(b?.message||'Unable to initiate payout'),{status:502})}
  await patch('payout_requests',`id=eq.${pr.id}`,{status:'queued',provider_payload:b,provider_ref:b?.data?.reference||b?.data||null});pr={...pr,status:'queued'};const vr=await verifyPayoutRow(pr);return {status:vr.state,payout_ref:pr.payout_ref}
}

Deno.serve(async(req)=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers:cors});if(req.method!=='POST')return json({error:'Method not allowed'},405);
  try{
    const uid=await authenticatedUser(req);const body=await req.json().catch(()=>({}));const action=String(body?.action||'');
    if(action==='fund_escrow'&&(!(await featureAvailable('earn_work'))||!(await featureAvailable('payments'))))return json({error:'New escrow funding is temporarily disabled by the Mela administrator.',code:'FEATURE_DISABLED'},503);
    if(action==='list_banks'&&!(await featureAvailable('payouts')))return json({error:'Payouts are temporarily disabled by the Mela administrator.',code:'FEATURE_DISABLED'},503);
    if(action==='payout'&&!(await featureAvailable('payouts')))return json({error:'Payouts are temporarily disabled by the Mela administrator.',code:'FEATURE_DISABLED'},503);
    let out:any;
    if(action==='fund_escrow')out=await fundEscrow(uid,body);
    else if(action==='verify_escrow')out=await verifyEscrow(uid,body);
    else if(action==='list_banks')out=await listBanks();
    else if(action==='payout'||action==='verify_payout')out=await payout(uid,{...body,action:action==='verify_payout'?'verify':body?.action});
    else return json({error:'Unknown action'},400);
    return json(out)
  }catch(e:any){console.error('mela-finance',e);return json({code:e?.code,error:e instanceof Error?e.message:'Unexpected error'},e?.status||500)}
});