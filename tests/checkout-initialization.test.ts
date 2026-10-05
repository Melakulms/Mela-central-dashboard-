import { readFileSync } from 'node:fs'
import { webcrypto } from 'node:crypto'
import ts from 'typescript'
import { describe, it, expect } from 'vitest'
const names=['chapa-initialize','mela-learning-checkout','mela-finance']
const codes=Object.fromEntries(names.map(n=>[n,ts.transpileModule(readFileSync(new URL(`../supabase/functions/${n}/index.ts`,import.meta.url),'utf8').replace(/^import .*\n/gm,''),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText]))
function api(name:string, options:{enabled?:boolean;auth?:boolean;open?:boolean;processing?:boolean;collision?:boolean;amount?:number;currency?:string;providerHttp?:number;checkout?:string;networkFailure?:boolean}={}){
 let handler:any
 const requests:{url:string;init:RequestInit}[]=[]
 const amount=options.amount??2000,currency=options.currency??'ETB'
 const fetch=async(url:string,init:RequestInit={})=>{
  requests.push({url,init});let body:any=[];let status=200
  if(url.includes('/auth/v1/user')){body={id:'actor-id',email:'local@example.invalid'};status=options.auth===false?401:200}
  else if(url.includes('rpc/platform_feature_available'))body=options.enabled!==false
  else if(url.includes('courses?'))body=[{id:'course-id',slug:'course',title:'Local course',price_cents:amount,currency}]
  else if(url.includes('mela_learning_products?'))body=[{product_key:'product',product_name:'Local product',product_type:'subscription',sale_enabled:true,active_price_minor:amount,currency,audience_stage_keys:[]}]
  else if(url.includes('escrow_transactions?'))body=[{id:'escrow-id',contract_id:'contract-id',transaction_type:'funding',status:'funding_pending',amount_minor:amount,currency}]
  else if(url.includes('freelance_contracts?'))body=[{id:'contract-id',employer_id:'employer-id'}]
  else if(url.includes('employers?'))body=[{owner_id:'actor-id'}]
  else if(url.includes('profiles?'))body=[{full_name:'Local payer',email:'local@example.invalid'}]
  else if(url.includes('select=tx_ref'))body=options.open?[{tx_ref:'existing-ref',status:'pending',mode:'test',expected_currency:'ETB',checkout_url:options.processing?null:'https://checkout.example.invalid/existing',expected_amount_cents:amount,expected_amount_minor:amount}]:[]
  else if(init.method==='PATCH')body=[{id:'attempt-id',status:'pending'}]
  else if(init.method==='POST'&&!url.includes('api.chapa.co')){body=options.collision?{code:'23505',message:'duplicate open checkout'}:[{id:'attempt-id'}];status=options.collision?409:200}
  else if(url.includes('api.chapa.co')){if(options.networkFailure)throw new Error('local simulated timeout');status=options.providerHttp||200;body={status:'success',data:{checkout_url:options.checkout??'https://checkout.example.invalid/new'}}}
  return new Response(JSON.stringify(body),{status})
 }
 const env:Record<string,string>={SUPABASE_URL:'https://example.invalid',SUPABASE_ANON_KEY:'local-public',SUPABASE_SERVICE_ROLE_KEY:'local-service',CHAPA_SECRET_KEY:'CHASECK_TEST_FAKE',MELA_PAYMENT_MODE:'test'}
 new Function('Deno','fetch','crypto',codes[name])({env:{get:(k:string)=>env[k]},serve:(h:any)=>handler=h},fetch,webcrypto)
 return{requests,request:()=>handler(new Request('https://example.invalid',{method:'POST',headers:{Authorization:'Bearer local-token','Content-Type':'application/json'},body:JSON.stringify({action:'fund_escrow',escrow_id:'escrow-id',course_slug:'course',product_key:'product'})}))}
}
const providerCalls=(s:ReturnType<typeof api>)=>s.requests.filter(r=>r.url.includes('api.chapa.co'))
for(const name of names)describe(name+' checkout',()=>{
 it('does not create a checkout when financial gates are disabled',async()=>{const s=api(name,{enabled:false});expect((await s.request()).status).toBe(503);expect(providerCalls(s)).toHaveLength(0)})
 it('validates identity before reading payer records',async()=>{const s=api(name,{auth:false});expect((await s.request()).status).toBe(401);expect(s.requests.some(r=>r.url.includes('profiles?'))).toBe(false);expect(providerCalls(s)).toHaveLength(0)})
 it('reuses an existing checkout without initializing another',async()=>{const s=api(name,{open:true});const r=await s.request();expect(r.status).toBe(200);expect(await r.json()).toMatchObject({reused:true,tx_ref:'existing-ref'});expect(providerCalls(s)).toHaveLength(0)})
 it('blocks retry while an earlier checkout has an uncertain result',async()=>{const s=api(name,{open:true,processing:true});expect((await s.request()).status).toBe(409);expect(providerCalls(s)).toHaveLength(0)})
 it('stops before provider access when another request wins the database claim',async()=>{const s=api(name,{collision:true});expect((await s.request()).status).toBe(409);expect(providerCalls(s)).toHaveLength(0)})
 it.each([{amount:2000.5},{amount:0},{currency:'USD'}])('rejects invalid server-side price %j',async config=>{const s=api(name,config);expect((await s.request()).status).toBeGreaterThanOrEqual(400);expect(providerCalls(s)).toHaveLength(0)})
 it.each(['javascript:alert(1)','http://checkout.example.invalid','https://user:password@checkout.example.invalid'])('rejects unsafe checkout address %s',async checkout=>{const s=api(name,{checkout});expect((await s.request()).status).toBe(502);expect(s.requests.filter(r=>r.init.method==='PATCH').every(r=>JSON.parse(String(r.init.body)).status!=='failed')).toBe(true)})
 it('does not fail an attempt when provider response is uncertain',async()=>{const s=api(name,{providerHttp:500});expect((await s.request()).status).toBe(502);const patch=s.requests.find(r=>r.init.method==='PATCH')!;expect(patch.url).toContain('status=eq.initiated');expect(JSON.parse(String(patch.init.body)).status).toBeUndefined()})
 it('keeps a timed-out attempt available for reconciliation',async()=>{const s=api(name,{networkFailure:true});expect((await s.request()).status).toBeGreaterThanOrEqual(500);expect(s.requests.some(r=>r.init.method==='PATCH')).toBe(false)})
 it('creates one checkout and only changes an initiated attempt to pending',async()=>{const s=api(name);expect((await s.request()).status).toBe(200);expect(providerCalls(s)).toHaveLength(1);const patch=s.requests.find(r=>r.init.method==='PATCH')!;expect(patch.url).toContain('status=eq.initiated');expect(JSON.parse(String(patch.init.body)).status).toBe('pending')})
})
