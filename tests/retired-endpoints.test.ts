import {readFileSync} from 'node:fs'
import {expect,it} from 'vitest'

it.each(['mela-admin','mela-source-recheck-v30'])('retires %s without any database or network access',async slug=>{
  const source=readFileSync(new URL(`../supabase/functions/${slug}/index.ts`,import.meta.url),'utf8')
  let handler:any
  new Function('Deno',source)({serve:(h:any)=>handler=h})
  for(const method of ['GET','POST','DELETE','OPTIONS']) {
    const response=await handler(new Request('https://example.invalid',{method}))
    expect(response.status).toBe(410)
    expect(response.headers.get('Cache-Control')).toBe('no-store')
  }
  expect(source).not.toMatch(/fetch\(|createClient|Deno\.env/)
})
