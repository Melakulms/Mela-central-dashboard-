import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { stripTypeScriptTypes } from 'node:module';
const source=stripTypeScriptTypes(fs.readFileSync(new URL('./index.ts',import.meta.url),'utf8').replace(/^import .*\n/gm,''),{mode:'transform'});
async function run({url='https://tungqfmypuwzeyrtaseh.supabase.co',method='POST',origin='https://mela-admin-staging.vercel.app',authorization,validUser=false,profileActive=true,admin=false,aal='aal1',registryError=false}) {
  let handler;let reads=0;
  const client={
    auth:{getUser:async()=>({data:{user:validUser?{id:'fixture'}:null},error:validUser?null:new Error('invalid')}),
      mfa:{getAuthenticatorAssuranceLevel:async()=>({data:{currentLevel:aal},error:null})}},
    from(table){reads++; return {select(){return this},eq(){return this},maybeSingle:async()=>({data:table==='profiles'?{account_status:profileActive?'active':'suspended'}:admin?{role_id:'role',active:true,mfa_required:true}:null,error:table==='admin_users'&&registryError?{code:'permission_denied'}:null}),single:async()=>({data:{key:'super_admin',name:'Super Admin'},error:null})}},
    schema(){return this}
  };
  vm.runInNewContext(source,{Deno:{env:{get:k=>k==='SUPABASE_URL'?url:'unused'},serve:h=>handler=h},createClient:()=>client,Response,crypto,console,Set,Date});
  const headers={Origin:origin,'Content-Type':'application/json'};
  if(authorization) headers.Authorization=authorization;
  const response=await handler(new Request('https://example.invalid',{method,headers,...(method==='POST'?{body:'{"action":"me"}'}:{})}));
  return {response,reads};
}
const cases=[
 ['wrong project',{url:'https://duizgtmbptmlbyipreqg.supabase.co'},503],
 ['production origin',{origin:'https://central-dashboard-gamma.vercel.app'},403],
 ['untrusted origin',{origin:'https://evil.invalid'},403],
 ['preflight',{method:'OPTIONS'},200],
 ['unsupported method',{method:'GET'},405],
 ['missing authentication',{},401],
 ['invalid session',{authorization:'Bearer invalid'},401],
 ['inactive profile',{authorization:'Bearer fixture',validUser:true,profileActive:false},403],
 ['no admin membership',{authorization:'Bearer fixture',validUser:true},403],
 ['registry unavailable',{authorization:'Bearer fixture',validUser:true,registryError:true},503],
 ['aal1 administrator',{authorization:'Bearer fixture',validUser:true,admin:true},403]
];
for(const [name,options,status] of cases){const {response,reads}=await run(options);assert.equal(response.status,status,name);if(['wrong project','production origin','untrusted origin','missing authentication','preflight'].includes(name))assert.equal(reads,0,name);if(name==='preflight')assert.equal(response.headers.get('Access-Control-Allow-Origin'),'https://mela-admin-staging.vercel.app');console.log('PASS',name);}
