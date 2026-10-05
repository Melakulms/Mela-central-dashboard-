import {readFileSync} from 'node:fs'
import ts from 'typescript'
import {webcrypto} from 'node:crypto'
import {describe,it,expect} from 'vitest'
const code=ts.transpileModule(readFileSync(new URL('../supabase/functions/mela-ai-execution-v2/index.ts',import.meta.url),'utf8').replace(/^import .*;$/gm,''),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.None}}).outputText
function api(owner='user-a'){
 let handler:any;const calls:{url:string,body:any}[]=[];
 const fetch=async(url:string,init:any={})=>{
  const body=init.body?JSON.parse(init.body):null;calls.push({url,body});let data:any=[];
  if(url.includes('/auth/v1/user'))data={id:'user-a'};
  else if(url.includes('/profiles?')){if(!url.includes('&id=eq.user-a'))return new Response('{}',{status:400});data=[{id:'user-a',role:'student'}]}
  else if(url.includes('/mela_ai_tasks?'))data=[{id:'task-a',created_by:owner,assigned_agent_id:'agent-a',description:'Explain fractions',status:'queued',approval_status:'not_required'}];
  else if(url.includes('/mela_ai_agents?'))data=[{id:'agent-a',agent_key:'student',name:'Tutor',enabled:true}];
  else if(url.endsWith('/mela_ai_runs'))data=[{id:'run-a'}];
  else if(url.includes('/functions/v1/mela-openai-proxy'))data={message:{content:'A fraction represents part of a whole.'}};
  return new Response(JSON.stringify(data));
 };
 const env:any={SUPABASE_URL:'https://local.invalid',SUPABASE_ANON_KEY:'public',SUPABASE_SERVICE_ROLE_KEY:'server'};
 new Function('Deno','fetch','crypto',code)({env:{get:(k:string)=>env[k]},serve:(h:any)=>handler=h},fetch,webcrypto);
 return {calls,request:(body:any)=>handler(new Request('https://local.invalid',{method:'POST',headers:{Authorization:'Bearer fixture'},body:JSON.stringify(body)}))};
}
describe('AI execution boundary',()=>{
 it('loads the caller profile using a valid equality filter',async()=>{const s=api();expect((await s.request({message:'Explain fractions'})).status).toBe(200)});
 it('loads queued task text without requiring client resubmission',async()=>{const s=api();expect((await s.request({task_id:'task-a'})).status).toBe(200);expect(s.calls.find(x=>x.url.includes('/functions/'))?.body.messages[1].content).toBe('Explain fractions')});
 it('denies another user task without writes or model calls',async()=>{const s=api('user-b');expect((await s.request({task_id:'task-a'})).status).toBe(403);expect(s.calls.some(x=>x.body)).toBe(false)});
 it('denies report export before privileged reads',async()=>{const s=api();expect((await s.request({message:'generate report'})).status).toBe(403);expect(s.calls.some(x=>x.url.includes('/reports?'))).toBe(false)});
});
