import { readFileSync } from 'node:fs'
import { createHmac, webcrypto } from 'node:crypto'
import ts from 'typescript'
import { describe, it, expect, vi } from 'vitest'

const names = ['chapa-verify', 'chapa-callback', 'mela-learning-payment-verify', 'mela-learning-payment-callback']
const codes = Object.fromEntries(names.map(name => [name, ts.transpileModule(readFileSync(new URL(`../supabase/functions/${name}/index.ts`, import.meta.url), 'utf8'), { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText]))
function api(name: string, options: { data?: any; attempt?: any; http?: number; invalidAuth?: boolean; malformed?: boolean; concurrentFailure?: boolean } = {}) {
  let handler: any
  const requests: { url: string; init: RequestInit }[] = []
  const attempt = { id: 'attempt-id', user_id: 'user-id', course_id: 'course-id', mode: 'test', tx_ref: 'ref', status: 'pending', expected_amount_cents: 1000, expected_amount_minor: 1000, expected_currency: 'ETB', ...options.attempt }
  const fetch = vi.fn(async (url: string, init: RequestInit = {}) => {
    requests.push({ url, init }); let body: any = []; let status = 200
    if (url.includes('/auth/v1/user')) { body = { id: 'user-id' }; status = options.invalidAuth ? 401 : 200 }
    else if (url.includes('api.chapa.co')) {
      status = options.http || 200
      body = options.malformed ? {} : { status: 'success', data: { status: 'success', amount: '10.00', currency: 'ETB', mode: 'test', tx_ref: 'ref', reference: 'provider-ref', ...options.data } }
    } else if (url.includes('rpc/finalize_mela_learning_payment')) body = { status: 'success' }
    else if (url.includes('payments?') || url.includes('mela_learning_payment_attempts?')) {
      body = options.concurrentFailure && init.method === 'PATCH' ? [] : [{ ...attempt, ...(options.concurrentFailure && url.includes('select=status') ? { status: 'failed' } : {}) }]
    }
    return new Response(JSON.stringify(body), { status })
  })
  const env: Record<string, string> = { SUPABASE_URL: 'https://example.invalid', SUPABASE_ANON_KEY: 'local-public-key', SUPABASE_SERVICE_ROLE_KEY: 'local-service-key', CHAPA_SECRET_KEY: 'CHASECK_TEST_FAKE', CHAPA_WEBHOOK_SECRET: 'local-webhook-key', MELA_PAYMENT_MODE: 'test' }
  new Function('Deno', 'fetch', 'crypto', codes[name])({ env: { get: (key: string) => env[key] }, serve: (h: any) => { handler = h } }, fetch, webcrypto)
  return { requests, request: () => {
    const body = JSON.stringify({ tx_ref: 'ref' })
    return handler(new Request('https://example.invalid', { method: 'POST', headers: { Authorization: 'Bearer local-token', 'x-chapa-signature': options.invalidAuth ? 'invalid' : createHmac('sha256', env.CHAPA_WEBHOOK_SECRET).update(body).digest('hex') }, body }))
  } }
}
const successWrite = (server: ReturnType<typeof api>) => server.requests.some(r => r.url.includes('rpc/finalize_mela_learning_payment') || (r.init.method === 'PATCH' && JSON.parse(String(r.init.body)).status === 'success'))
for (const name of names) describe(name, () => {
  it('rejects invalid authentication before payment reads', async () => {
    const server = api(name, { invalidAuth: true }); expect((await server.request()).status).toBe(401)
    expect(server.requests.some(r => r.url.includes('/rest/v1/'))).toBe(false)
  })
  it.each([{ amount: '10.001' }, { amount: '1e1' }, { amount: null }, { amount: '9.99' }, { mode: 'live' }, { currency: 'USD' }, { tx_ref: 'other' }, { reference: '' }])('rejects inconsistent provider result %j', async data => {
    const server = api(name, { data }); expect((await server.request()).status).toBe(409); expect(successWrite(server)).toBe(false)
  })
  it('rejects a cross-environment attempt before provider access', async () => {
    const server = api(name, { attempt: { mode: 'live' } }); expect((await server.request()).status).toBe(409)
    expect(server.requests.some(r => r.url.includes('api.chapa.co'))).toBe(false)
  })
  it('leaves existing state unchanged on provider failure', async () => {
    const server = api(name, { http: 503 }); expect((await server.request()).status).toBe(503)
    expect(server.requests.some(r => r.init.method === 'PATCH')).toBe(false); expect(successWrite(server)).toBe(false)
  })
  it('rejects an incomplete provider response', async () => {
    const server = api(name, { malformed: true }); expect((await server.request()).status).toBe(503); expect(successWrite(server)).toBe(false)
  })
  it('restricts a delayed pending response to unfinished rows', async () => {
    const server = api(name, { data: { status: 'pending' } }); await server.request()
    expect(server.requests.find(r => r.init.method === 'PATCH')?.url).toContain('&status=in.(initiated,pending)')
  })
  it('does not re-verify a successful payment', async () => {
    const server = api(name, { attempt: { status: 'success' } }); expect((await server.request()).status).toBe(200)
    expect(server.requests.some(r => r.url.includes('api.chapa.co'))).toBe(false); expect(successWrite(server)).toBe(false)
  })
  it('completes a matching provider-verified payment', async () => {
    const server = api(name); expect((await server.request()).status).toBe(200); expect(successWrite(server)).toBe(true)
  })
  if (name.endsWith('verify')) it('scopes the payment lookup to the authenticated user', async () => {
    const server = api(name); await server.request()
    expect(server.requests.find(r => r.url.includes('select=*'))?.url).toContain('user_id=eq.user-id')
  })
})
it.each(['chapa-verify','chapa-callback'])('%s does not report success after losing a race to a failed payment state', async name => {
  const server = api(name, { concurrentFailure: true }); expect((await server.request()).status).toBe(409)
  expect(server.requests.some(r => r.url.includes('course_enrollments'))).toBe(false)
})

it.each(['mela-learning-payment-verify','mela-learning-payment-callback'])('%s passes paid minor units, not provider fees, to the database',async name=>{
 const server=api(name,{data:{amount:'10.00',charge:'0.25'}});await server.request();
 const call=server.requests.find(r=>r.url.includes('rpc/finalize_mela_learning_payment'))!;
 expect(JSON.parse(String(call.init.body)).p_provider_charge).toBe(1000);
});
