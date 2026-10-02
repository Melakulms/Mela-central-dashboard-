import {readFileSync} from 'node:fs'
import ts from 'typescript'
import {describe,it,expect,vi} from 'vitest'
const source=readFileSync(new URL('../supabase/functions/mela-finance/index.ts',import.meta.url),'utf8').replace(/^import .*\n/gm,'')
const code=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText
function api(status='pending',enabled=true,provider:any={status:'success',data:{status:'pending'}},valid=true){
 let handler:any
 const payout={id:'payout-id',milestone_id:'milestone-id',escrow_id:'escrow-id',payout_ref:'payout-reference',amount_minor:1000,currency:'ETB',status}
 const requests:{url:string;method:string}[]=[]
 const fetch=vi.fn(async(url:string,init:RequestInit={})=>{
  requests.push({url,method:init.method??'GET'})
  let body:any=[];let http=200
  if(url.includes('/auth/v1/user')){body={id:'actor-id'};http=valid?200:401}
  else if(url.includes('rpc/platform_feature_available'))body=enabled
  else if(url.includes('task_milestones?'))body=[{id:'milestone-id',contract_id:'contract-id',status:'approved'}]
  else if(url.includes('freelance_contracts?'))body=[{id:'contract-id',employer_id:'employer-id',freelancer_id:'student-id'}]
  else if(url.includes('profiles?'))body=[{role:'admin',account_status:'active'}]
  else if(url.includes('payout_requests?')&&init.method!=='PATCH')body=[payout]
  else if(url.includes('payout_accounts?'))body=[{account_name:'Test account',account_number:'123',bank_code:1}]
  else if(url.includes('rpc/claim_mela_payout'))body={...payout,status:'queued'}
  else if(url.includes('api.chapa.co'))body=provider
  return new Response(JSON.stringify(body),{status:http})
 })
 new Function('Deno','fetch',code)({env:{get:(key:string)=>key==='CHAPA_SECRET_KEY'?'CHASECK_TEST_FAKE':key==='MELA_PAYMENT_MODE'?'test':'https://example.invalid'},serve:(h:any)=>handler=h},fetch)
 return {requests,request:(action:string)=>handler(new Request('https://example.invalid',{method:'POST',headers:{Authorization:'Bearer test-token','Content-Type':'application/json'},body:JSON.stringify({action,milestone_id:'milestone-id'})}))}
}
describe('Finance transfer boundary',()=>{
 it.each(['pending','failed','queued'])('verification never initiates a %s transfer',async status=>{
  const server=api(status,false);expect((await server.request('verify_payout')).status).toBe(200)
  expect(server.requests.some(r=>r.url.endsWith('/v1/transfers')&&r.method==='POST')).toBe(false)
 })
 it('keeps disabled payouts closed',async()=>{const server=api('pending',false);expect((await server.request('payout')).status).toBe(503);expect(server.requests.some(r=>r.url.includes('api.chapa.co'))).toBe(false)})
 it('does not resubmit queued transfers',async()=>{const server=api('queued');await server.request('payout');expect(server.requests.some(r=>r.url.endsWith('/v1/transfers'))).toBe(false)})
 it('claims a pending request before initiating the provider call',async()=>{
  const server=api();await server.request('payout');const claim=server.requests.findIndex(r=>r.url.includes('rpc/claim_mela_payout'));const transfer=server.requests.findIndex(r=>r.url.endsWith('/v1/transfers'))
  expect(claim).toBeGreaterThan(-1);expect(transfer).toBeGreaterThan(claim)
 })
 it('does not mistake an API success envelope for a paid transfer',async()=>{const server=api('queued',true,{status:'success'});await server.request('verify_payout');expect(server.requests.some(r=>r.url.includes('rpc/record_milestone_payout'))).toBe(false)})
 it('rejects mismatched successful verification',async()=>{const server=api('queued',true,{data:{status:'success',reference:'wrong',amount:10,currency:'ETB'}});await server.request('verify_payout');expect(server.requests.some(r=>r.url.includes('rpc/record_milestone_payout'))).toBe(false)})
 it('rejects an invalid session before reading financial records',async()=>{const server=api('pending',true,{},false);expect((await server.request('payout')).status).toBe(401);expect(server.requests).toHaveLength(1)})
})
