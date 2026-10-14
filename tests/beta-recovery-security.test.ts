import { readFileSync } from 'node:fs'
import ts from 'typescript'
import { describe, expect, it } from 'vitest'

const source=readFileSync(new URL('../supabase/functions/mela-beta-auth/index.ts',import.meta.url),'utf8').replace(/^import .*$/gm,'')
const code=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.None}}).outputText
const recoveryCode='MELA-R-test-only-recovery-code-not-a-real-credential'
async function hash(value:string) { return [...new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value)))].map(n=>n.toString(16).padStart(2,'0')).join('') }

async function api({passwordError=false,parallelReads=false,denyRate=false,rotationError=false}={}) {
  let handler:any, storedHash=await hash(recoveryCode), passwordWrites=0, readers=0
  const rateKeys:string[]=[]
  let release!:()=>void
  const barrier=new Promise<void>(resolve=>release=resolve)
  const db:any={
    auth:{admin:{updateUserById:async()=>{passwordWrites++;return {error:passwordError?{message:'failed'}:null}}}},
    rpc:async(_name:string,args:any)=>{rateKeys.push(args.p_key_hash);return {data:!denyRate,error:null}},
    from:(table:string)=>{
      let patch:any, filters:Record<string,any>={}
      const q:any={
        select:()=>q, eq:(key:string,value:any)=>{filters[key]=value;return q},
        update:(value:any)=>{patch=value;return q},
        maybeSingle:async()=>{
          if(table==='platform_feature_flags') return {data:{enabled:true},error:null}
          if(table==='profiles') return {data:{id:'fixture-user'},error:null}
          if(!patch) {
            const snapshot=storedHash
            if(parallelReads) { if(++readers===2) release(); await barrier }
            return {data:{recovery_hash:snapshot},error:null}
          }
          if(rotationError) return {data:null,error:{message:'failed'}}
          if(filters.recovery_hash!==storedHash) return {data:null,error:null}
          storedHash=patch.recovery_hash
          return {data:{user_id:'fixture-user'},error:null}
        },
        then:(resolve:any,reject:any)=>q.maybeSingle().then(resolve,reject),
      }
      return q
    },
  }
  new Function('Deno','createClient',code)({env:{get:()=> 'test-config'},serve:(h:any)=>handler=h},()=>db)
  return {rateKeys,get passwordWrites(){return passwordWrites},get storedHash(){return storedHash},
    request:(ip='192.0.2.1',extra:Record<string,unknown>={})=>handler(new Request('https://example.invalid/recovery',{
      method:'POST',headers:{'content-type':'application/json','x-forwarded-for':ip},
      body:JSON.stringify({action:'reset_password',username:'fixture.user',recovery_code:recoveryCode,new_password:'TestOnlyPassword123!',...extra}),
    })),
  }
}

describe('one-time password recovery',()=>{
  it('allows only one concurrent request to change a password',async()=>{
    const s=await api({parallelReads:true})
    const responses=await Promise.all([s.request(),s.request()])
    expect(responses.map(r=>r.status).sort()).toEqual([200,400])
    expect(s.passwordWrites).toBe(1)
    const result=await responses.find(r=>r.status===200)!.json()
    expect(await hash(result.recovery_code)).toBe(s.storedHash)
  })
  it('rejects replay after a successful reset',async()=>{
    const s=await api();expect((await s.request()).status).toBe(200)
    expect((await s.request()).status).toBe(400);expect(s.passwordWrites).toBe(1)
  })
  it('restores the consumed code when the password provider fails',async()=>{
    const s=await api({passwordError:true});expect((await s.request()).status).toBe(500)
    expect(s.storedHash).toBe(await hash(recoveryCode))
  })
  it('does not change the password if the atomic claim fails',async()=>{
    const s=await api({rotationError:true});expect((await s.request()).status).toBe(500);expect(s.passwordWrites).toBe(0)
  })
  it('keeps account throttling independent of client-supplied IP headers',async()=>{
    const s=await api({denyRate:true})
    expect((await s.request('192.0.2.1')).status).toBe(429)
    expect((await s.request('192.0.2.2')).status).toBe(429)
    expect(s.rateKeys[0]).not.toBe(s.rateKeys[2]);expect(s.rateKeys[1]).toBe(s.rateKeys[3])
    expect(s.passwordWrites).toBe(0)
  })
  it('rejects oversized recovery credentials before database writes',async()=>{
    const s=await api()
    expect((await s.request(undefined,{new_password:'Aa1'.repeat(100)})).status).toBe(400)
    expect((await s.request(undefined,{recovery_code:'x'.repeat(201)})).status).toBe(400)
    expect(s.passwordWrites).toBe(0)
  })
})
