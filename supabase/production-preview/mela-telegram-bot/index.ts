import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// MELA production Telegram: informational commands only.
// No collection, payment verification, entitlements, test payments, or account linking.
const PROJECT_URL = "https://duizgtmbptmlbyipreqg.supabase.co";
const STAGING_WEBHOOK = "https://tungqfmypuwzeyrtaseh.supabase.co/functions/v1/mela-telegram-bot";
const FUNCTION_NAME = "mela-telegram-bot";
const BOT_USERNAME = "mela_edu_bot";
const enc = new TextEncoder();

function sendJson(payload: unknown, status=200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {"content-type":"application/json; charset=utf-8","cache-control":"no-store"},
  });
}

function config() {
  const token = Deno.env.get("MELA_TELEGRAM_BOT_TOKEN") || "";
  const secret = Deno.env.get("MELA_TELEGRAM_WEBHOOK_SECRET") || "";
  const project = Deno.env.get("SUPABASE_URL") || "";
  const ready = project === PROJECT_URL &&
    /^[0-9]{5,}:[A-Za-z0-9_-]{20,}$/.test(token) &&
    /^[A-Za-z0-9_-]{32,256}$/.test(secret);
  return {token, secret, ready, projectMatches:project===PROJECT_URL};
}

function safeEqual(a:string, b:string):boolean {
  const x=enc.encode(a), y=enc.encode(b);
  if (x.length!==y.length) return false;
  let diff=0;
  for(let i=0;i<x.length;i++) diff|=x[i]^y[i];
  return diff===0;
}

async function telegram(token:string,method:string,payload:Record<string,unknown>) {
  const r=await fetch("https://api.telegram.org/bot"+token+"/"+method,{
    method:"POST",
    headers:{"content-type":"application/json"},
    body:JSON.stringify(payload),
    signal:AbortSignal.timeout(10000),
  });
  if(!r.ok) throw new Error("telegram_transport_error");
  const response=await r.json();
  if(response?.ok!==true) throw new Error("telegram_api_error");
  return response.result;
}

async function paymentRpc(action:string,data:Record<string,unknown>={}){
 const key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')||'';
 if(!key) throw new Error('Payment service unavailable. Please try again later.');
 const response=await fetch(PROJECT_URL+'/rest/v1/rpc/mela_telegram_payment_bot_v1',{
 method:'POST',headers:{apikey:key,authorization:'Bearer '+key,'content-type':'application/json'},
 body:JSON.stringify({p_action:action,p_data:data}),signal:AbortSignal.timeout(10000)});
 const result=await response.json();
 if(!response.ok){
   if(result.code==='P0001')throw new Error(String(result.message).slice(0,250));
   if(result.code==='23505')throw new Error('That reference has already been submitted. Check /status.');
   throw new Error('Payment service unavailable. No approval was made. Please try again later.');
 }
 return result;
}
function parseSubmission(text:string){
 const p=text.trim().split(/\s+/);const provider=p[1]?.toLowerCase();
 if(!['dashen','telebirr'].includes(provider)||!/^\d+(?:\.\d{1,2})?$/.test(p[2]||''))return null;
 const parts=p[2].split('.');const amount=Number(parts[0])*100+Number((parts[1]||'').padEnd(2,'0'));
 const reference=(p[3]||'').toUpperCase();const details=p.slice(4).join(' ');
 if(!Number.isSafeInteger(amount)||amount<100||amount>100000000||!/^[A-Z0-9][A-Z0-9-]{5,63}$/.test(reference)||details.length<5||details.length>200)return null;
 return {provider,amount_minor:amount,reference,details};
}
async function livePaymentReply(text:string,message:any,updateId:number):Promise<string|null>{
 const cmd=text.trim().split(/\s+/)[0].toLowerCase().split('@')[0];
 if(cmd==='/pay'){
  const data=await paymentRpc('accounts');
  if(!data.enabled)return 'Payment submissions are temporarily paused. Do not send a new payment yet.';
  const accounts=(data.accounts||[]).map((a:any)=>`${a.provider==='dashen'?'Dashen Bank':'Telebirr'}\nAccount: ${a.recipient}\nHolder: ${a.holder}`).join('\n\n');
  return 'MELA payment instructions\n\n'+accounts+'\n\nPay only for a MELA service and amount already agreed with MELA. Foundational Free Core remains free. Confirm the recipient name in your banking app before transferring.\n\nAfter transferring, send /verify for submission instructions. Payment approval is manual after checking the actual incoming money. Never send your PIN, password, OTP or receipt screenshot.';
 }
 if(cmd==='/verify'){
  const parsed=parseSubmission(text);
  if(!parsed)return 'Submit your real payment using this format:\n\n/verify telebirr AMOUNT REFERENCE PAYER NAME - SERVICE\n\nUse dashen instead of telebirr for Dashen Bank. Replace AMOUNT with the birr you paid, REFERENCE with the actual transaction reference, and add the payer name and service.\n\nExample format only (do not copy the example reference):\n/verify telebirr 50 YOURREF123 Melaku Anteneh - agreed course\n\nA submitted reference is not approval. MELA checks the receiving account manually. Send /status to follow progress.';
  const data=await paymentRpc('submit',{...parsed,chat_id:String(message.chat.id),update_id:updateId,claimant:[message.from.first_name,message.from.last_name,message.from.username?'@'+message.from.username:''].filter(Boolean).join(' ')});
  return (data.duplicate?'This payment is already recorded.':'Payment reference received.')+'\nCase: '+data.id+'\nStatus: '+data.status+'\n\n'+(data.status==='verified'?'MELA manually verified the incoming payment.':data.status==='rejected'?'Use /status to read the review result.':'Awaiting MELA review of the actual incoming transfer. This is not yet proof of payment.')+'\nSend /status to check progress. Do not transfer again for the same purchase.';
 }
 if(cmd==='/status'){
  const rows=await paymentRpc('status',{chat_id:String(message.chat.id)});
  if(!rows.length)return 'No payment submissions in this Telegram chat yet. Use /verify after making an agreed payment.';
  return 'Your latest MELA payment submissions\n\n'+rows.map((r:any)=>`${r.amount_minor/100} ETB · ${r.provider}\nReference: ${r.reference}\nStatus: ${r.status==='verified'?'Manually verified':r.status==='pending'?'Awaiting manual review':'Rejected'}\nCase: ${r.id}${r.reason?'\nReason: '+r.reason:''}`).join('\n\n')+'\n\nVerified means MELA confirmed receipt. Service delivery is handled by MELA; this bot does not automatically enrol you in a course.';
 }
 return null;
}

function reply(input:string):string {
 const cmd=input.trim().split(/\s+/)[0].toLowerCase().split("@")[0];
 if(cmd==="/plans") return "MELA upcoming subscriptions (not yet available for purchase)\n\nFree Core: free\nPro: 50 ETB / 30 days\nPremium: 100 ETB / 30 days\n\nPlanned referral reward after a new member's FIRST independently verified paid subscription: Pro 20 ETB; Premium 40 ETB. No reward for sign-up alone.\n\nThese plans are not active in production checkout yet. Do NOT transfer money based on this message. Only follow a verified in-app payment order once MELA enables the new checkout.";
 if(cmd==="/start") return "Welcome to MELA Education! 🇪🇹\n\nUse /plans for upcoming subscriptions. Use /pay for current payment instructions, /verify to submit a transfer, and /status to check its review. Payments are reviewed manually. Free Core remains free.";
 if(cmd==="/privacy") return "MELA stores your Telegram chat ID, claimed name, payment references, amount, service description and review result to verify payments and resolve disputes. Only your chat can request its status; the authorized reviewer uses MFA. Never send PINs, passwords, OTPs, identity documents or screenshots.";
 if(cmd==="/review") return "MELA reviewer sign-in (authorized administrator only):\nhttps://mela-private-payment-test.cloudyjelly10.chatgpt.site";
 return "MELA Education Bot\n/start — Welcome\n/plans — Upcoming Pro and Premium prices (not yet purchasable)\n/pay — Receiving accounts and payment instructions\n/verify — Submit a real payment reference\n/status — Your payment review status\n/privacy — Data notice\n/review — Administrator review screen\n\nApproval follows manual confirmation in the receiving account. References alone do not approve payments.";
}

Deno.serve(async (req:Request):Promise<Response>=>{
  const cfg=config();
  const rawPath=new URL(req.url).pathname;
  const path=rawPath.startsWith("/functions/v1/") ? rawPath : "/functions/v1"+rawPath;
  const base="/functions/v1/"+FUNCTION_NAME;
  if(!cfg.projectMatches) return sendJson({ok:false,error:"project_mismatch"},503);

  if(req.method==="GET" && (path===base || path===base+"/health")){
    let webhookStatus="not_configured";
    let pendingUpdates:number|null=null;
    if(cfg.ready){
      try{
        const me=await telegram(cfg.token,"getMe",{});
        if(String(me?.username||"").toLowerCase()!==BOT_USERNAME) webhookStatus="bot_mismatch";
        else {
          const info=await telegram(cfg.token,"getWebhookInfo",{});
          webhookStatus=info?.url===PROJECT_URL+base ? "registered_here" : "registered_elsewhere";
          pendingUpdates=info?.pending_update_count ?? null;
        }
      }catch{webhookStatus="telegram_api_error";}
    }
    let paymentState=false;
    try { paymentState=(await paymentRpc("health")).enabled===true; } catch {}
    return sendJson({
      ok:true,service:"MELA Telegram production",
      configured:cfg.ready, bot:"@"+BOT_USERNAME,
      payments_enabled:paymentState,payment_mode:"manual_receipt_verification",account_linking_enabled:false,
      webhook_status:webhookStatus,pending_updates:pendingUpdates,
      supported_commands:["/start","/help","/plans","/pay","/verify","/status","/privacy"],
    });
  }
  // Deployment is complete. Setup never reclaims or moves the webhook.
  if(req.method==="POST" && (path===base+"/setup" || path===base+"/release-cutover" || req.headers.has("x-mela-telegram-setup-secret")))
    return sendJson({ok:false,error:"setup_disabled"},403);

  if(req.method==="POST" && path===base){
    if(!cfg.ready) return sendJson({ok:false,error:"not_configured"},503);
    if(!safeEqual(req.headers.get("x-telegram-bot-api-secret-token")||"",cfg.secret))
      return sendJson({ok:false,error:"unauthorized"},401);
    const length=Number(req.headers.get("content-length")||0);
    if(length>16384) return sendJson({ok:false,error:"payload_too_large"},413);
    let update:any;
    try{
      const body=await req.text();
      if(body.length>16384) return sendJson({ok:false,error:"payload_too_large"},413);
      update=JSON.parse(body);
    }catch{return sendJson({ok:false,error:"invalid_json"},400);}
    const message=update?.message, chat=message?.chat;
    if(!Number.isSafeInteger(update?.update_id)
      || chat?.type!=="private"
      || !Number.isSafeInteger(chat?.id)
      || message?.from?.id!==chat.id
      || message?.from?.is_bot){
      return sendJson({ok:true,ignored:true});
    }
    let answer:string;
    try {
      answer=typeof message.text==="string" && message.text.length<=4096
        ? (await livePaymentReply(message.text,message,update.update_id)) ?? reply(message.text)
        : "Attachments are not accepted. Send /verify to submit a transaction reference. Never send credentials or identity documents.";
    } catch(e) {
      answer=e instanceof Error ? e.message : "Payment service unavailable. Please try again later.";
    }
    try {
      await telegram(cfg.token,"sendMessage",{chat_id:chat.id,text:answer,protect_content:true});
      return sendJson({ok:true});
    } catch {
      return sendJson({ok:false,error:"reply_failed"},502);
    }
  }
  return sendJson({ok:false,error:"not_found"},404);
});
