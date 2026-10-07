import {readFileSync} from 'node:fs'
import ts from 'typescript'
import {describe,it,expect} from 'vitest'
const code=ts.transpileModule(readFileSync(new URL('../supabase/functions/mela-ai-admin/index.ts',import.meta.url),'utf8').replace(/^import .*$/gm,''),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.None}}).outputText
function api({aal='aal2',assuranceError=null,permissionError=null,role='super_admin',mfaRequired=true,rpcError=null}:any={}){
 let handler:any;let token:any;let reads=0;
 const mutations:any[]=[]; const db:any={rpc:async(name:string,args:any)=>{mutations.push({name,args});return {data:{data:{enabled:true}},error:rpcError}},schema:()=>db,from:(table:string)=>{
 const data:any=table==='admin_users'?{user_id:'u',role_id:'r',active:true,mfa_required:mfaRequired}:table==='roles'?{key:role}:table==='role_permissions'?[{permission_id:'p'}]:table==='permissions'?[{key:'system.manage'}]:[];
 if(table==='mela_ai_agents')reads++;
 const result={data,error:table==='permissions'?permissionError:null};
 const q:any={then:(resolve:any)=>Promise.resolve(result).then(resolve)};
 for(const key of ['select','eq','maybeSingle','single','in','order','limit'])q[key]=()=>q;
 return q;
 }};
 const caller={auth:{getUser:async()=>({data:{user:{id:'u'}},error:null}),mfa:{getAuthenticatorAssuranceLevel:async(t:any)=>{token=t;return {data:{currentLevel:aal},error:assuranceError}}}}};
 let clients=0;
 new Function('Deno','createClient',code)({env:{get:()=>undefined},serve:(h:any)=>handler=h},()=>++clients===1?caller:db);
 return {mutations,get token(){return token},get reads(){return reads},request:(origin='https://melakulms.github.io',method='POST',body:any={action:'agents.list'})=>handler(new Request('https://test.invalid',{method,headers:{Origin:origin,Authorization:'Bearer actual-session','x-request-id':'test'},...(method==='POST'?{body:JSON.stringify(body)}:{})}))};
}
describe('AI admin access boundary',()=>{
 it('accepts the production Pages origin and passes the bearer token to MFA',async()=>{const s=api();const r=await s.request();expect(r.status).toBe(200);expect(s.token).toBe('actual-session');expect(r.headers.get('Access-Control-Allow-Origin')).toBe('https://melakulms.github.io');expect(r.headers.get('Cache-Control')).toBe('no-store')});
 it('rejects unknown origins before database access',async()=>{const s=api();expect((await s.request('https://attacker.invalid')).status).toBe(403);expect(s.reads).toBe(0)});
 it('supports browser preflight',async()=>{const s=api();expect((await s.request(undefined,'OPTIONS')).status).toBe(200);expect(s.reads).toBe(0)});
 it.each([{aal:'aal1'},{aal:'aal1',mfaRequired:false},{assuranceError:{message:'failed'}}])('fails closed on MFA %j',async opts=>{const s=api(opts);expect((await s.request()).status).toBe(403);expect(s.reads).toBe(0)});
 it('fails closed on permission lookup failure',async()=>{const s=api({permissionError:{message:'failed'}});expect((await s.request()).status).toBe(500);expect(s.reads).toBe(0)});
});

it('saves a toggle through one atomic server-only call using the authenticated actor',async()=>{
 const s=api();expect((await s.request(undefined,'POST',{action:'agent.toggle',agent_id:'00000000-0000-4000-8000-000000000001',enabled:true,p_actor:'attacker'})).status).toBe(200);
 expect(s.mutations).toHaveLength(1);expect(s.mutations[0].args.p_actor).toBe('u');expect(s.mutations[0].name).toBe('mela_ai_admin_mutate');
});
it.each([['42501',403],['40001',409],['P0002',404],['22023',400],['XX000',500]])('reports mutation failure %s without a successful response',async(code,status)=>{
 const s=api({rpcError:{code}});expect((await s.request(undefined,'POST',{action:'agent.toggle',agent_id:'00000000-0000-4000-8000-000000000001',enabled:true})).status).toBe(status);
});
it('rejects a null request body',async()=>{const s=api();expect((await s.request(undefined,'POST',null)).status).toBe(400);expect(s.mutations).toHaveLength(0)});
