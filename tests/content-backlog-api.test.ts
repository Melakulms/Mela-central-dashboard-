import { readFileSync } from 'node:fs'
import ts from 'typescript'
import { expect, it, vi } from 'vitest'
const source = readFileSync(new URL('../supabase/functions/mela-content-admin/index.ts', import.meta.url), 'utf8').replace(/^import .*\n/gm, '')
const code = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText
function server(options: { permissions?: string[]; aal?: string; error?: boolean; fixtures?: Record<string, object> } = {}) {
 let handler: (req: Request) => Promise<Response>
 const queries: string[] = [], filters: unknown[][] = [], ranges: unknown[][] = []
 function query(result: object) {
  const b: any = {}
  for (const method of ['select','eq','in','order','range','ilike']) b[method] = (...args: unknown[]) => { if(method==='eq'||method==='ilike') filters.push(args); if(method==='range') ranges.push(args); return b }
  b.single=b.maybeSingle=()=>Promise.resolve(result)
  b.then=(resolve: any,reject: any)=>Promise.resolve(result).then(resolve,reject)
  return b
 }
 const caller={auth:{getUser:vi.fn().mockResolvedValue({data:{user:{id:'admin'}}}),mfa:{getAuthenticatorAssuranceLevel:vi.fn().mockResolvedValue({data:{currentLevel:options.aal??'aal2'}})}}}
 const db: any={schema:()=>db,from:(table: string)=>{queries.push(table);const fixtures:Record<string,object>={admin_users:{data:{role_id:'role',mfa_required:true}},roles:{data:{key:'content_editor'}},role_permissions:{data:[{permission_id:'permission'}]},permissions:{data:(options.permissions??['content.manage']).map(key=>({key}))}};return query(options.fixtures?.[table]??fixtures[table]??{data:[{title:'Course'}],count:53,error:options.error?{message:'failure'}:null})}}
 let calls=0
 new Function('Deno','createClient',code)({env:{get:()=> 'config'},serve:(h:typeof handler)=>{handler=h}},()=>calls++%2===0?caller:db)
 return {queries,filters,ranges,request:(body:object,auth=true)=>handler!(new Request('https://example.invalid',{method:'POST',headers:{'Content-Type':'application/json',...(auth?{Authorization:'Bearer token'}:{})},body:JSON.stringify(body)}))}
}
it('protects inventory and lesson text behind admin content permission and MFA',async()=>{
 const noAuth=server();expect((await noAuth.request({action:'courses.list'},false)).status).toBe(401);expect(noAuth.queries).toEqual([])
 const denied=server({permissions:[]});expect((await denied.request({action:'courses.lessons',course_id:'f8ab5edb-74ba-48f1-8bfe-a12444122a31'})).status).toBe(403);expect(denied.queries).not.toContain('course_lessons')
 expect((await server({aal:'aal1'}).request({action:'review.queue',kind:'questions'})).status).toBe(403)
})
it('returns exact totals and bounds course pagination and search',async()=>{
 const api=server();const res=await api.request({action:'courses.list',limit:999,offset:25,missing_only:true,search:'AI,(test)%'})
 expect(res.status).toBe(200);expect((await res.json()).total).toBe(53);expect(api.ranges).toEqual([[25,124]])
 expect(api.filters).toContainEqual(['content_available',false]);expect(api.filters).toContainEqual(['title','%AI  test  %'])
 expect(res.headers.get('Cache-Control')).toBe('no-store')
})
it('restricts question review batches by grade and subject without publication',async()=>{
 const api=server();expect((await api.request({action:'review.queue',kind:'questions',grade_level:8,program_key:'math-8',limit:25,offset:50})).status).toBe(200)
 expect(api.queries).toContain('mela_question_review_batches');expect(api.filters).toContainEqual(['grade_level',8]);expect(api.filters).toContainEqual(['program_key','math-8']);expect(api.ranges).toEqual([[50,74]])
})
it('rejects invalid queue kinds, grades and course IDs before accessing content',async()=>{
 for(const body of [{action:'review.queue',kind:'other'},{action:'review.queue',kind:'questions',grade_level:13},{action:'review.queue',kind:'chapters',grade_level:'8'},{action:'courses.lessons',course_id:'invalid'}]){
 const api=server();expect((await api.request(body)).status).toBe(400);expect(api.queries).not.toContain('course_lessons');expect(api.queries).not.toContain('mela_question_review_batches')
 }
})
it('returns inventory failures as errors rather than empty content',async()=>{
 expect((await server({error:true}).request({action:'courses.list'})).status).toBe(500)
 expect((await server({error:true}).request({action:'review.queue',kind:'chapters'})).status).toBe(500)
})

it('refuses incomplete course drafts before placing them in the review queue',async()=>{
 const id='f8ab5edb-74ba-48f1-8bfe-a12444122a31'
 const api=server({fixtures:{content_drafts:{data:{id,status:'draft',entity_type:'material',payload:{course_id:id,title:'Lesson',content_text:''}}}}})
 const response=await api.request({action:'draft.submit',draft_id:id})
 expect(response.status).toBe(400);expect((await response.json()).error).toContain('Complete the course lesson')
 expect(api.queries).not.toContain('courses')
})
it('rejects a complete-looking lesson draft for a missing course',async()=>{
 const id='f8ab5edb-74ba-48f1-8bfe-a12444122a31'
 const api=server({fixtures:{content_drafts:{data:{id,status:'draft',entity_type:'material',payload:{course_id:id,title:'Lesson',module_title:'Module',content_text:'Content '.repeat(20),objectives:['Learn a skill'],module_position:1,lesson_position:1,duration_minutes:10}}},courses:{data:null}}})
 const response=await api.request({action:'draft.submit',draft_id:id})
 expect(response.status).toBe(400);expect((await response.json()).error).toContain('no longer exists')
})
