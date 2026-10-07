import {readFileSync} from 'node:fs'
import ts from 'typescript'
import {webcrypto} from 'node:crypto'
import {it,expect} from 'vitest'
const code=ts.transpileModule(readFileSync(new URL('../supabase/functions/mela-ai-coordinator-v2/index.ts',import.meta.url),'utf8').replace(/^import .*;$/gm,''),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.None}}).outputText
it('creates an ordinary task at a valid approval level before execution',async()=>{
 let handler:any;let task:any;let executions=0;
 const fetch=async(url:string,init:any={})=>{
 let data:any=[];
 if(url.includes('/auth/v1/user'))data={id:'user-a'};
 else if(url.includes('/profiles?'))data=[{id:'user-a',role:'student'}];
 else if(url.includes('/mela_ai_agents?'))data=[{id:'agent-a',agent_key:'student',name:'Tutor'}];
 else if(url.endsWith('/mela_ai_tasks')){task=JSON.parse(init.body);if(task.approval_level<1||task.approval_level>3)return new Response('{}',{status:400});data=[{id:'task-a'}]}
 else if(url.includes('/functions/v1/')){executions++;data={ok:true,response:'A fraction is part of a whole.'}}
 return new Response(JSON.stringify(data));
 };
 new Function('Deno','fetch','crypto',code)({env:{get:(k:string)=>k==='SUPABASE_URL'?'https://local.invalid':'fixture'},serve:(h:any)=>handler=h},fetch,webcrypto);
 const response=await handler(new Request('https://local.invalid',{method:'POST',headers:{Authorization:'Bearer fixture'},body:JSON.stringify({message:'Explain fractions'})}));
 expect(response.status).toBe(200);expect(task.approval_level).toBe(1);expect(task.approval_status).toBe('not_required');expect(executions).toBe(1);
});
