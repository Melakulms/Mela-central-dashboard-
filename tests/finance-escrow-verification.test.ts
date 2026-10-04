import { readFileSync } from 'node:fs'
import ts from 'typescript'
import { describe, it, expect, vi } from 'vitest'
const source = readFileSync(new URL('../supabase/functions/mela-finance/index.ts', import.meta.url), 'utf8').replace(/^import .*\n/gm, '')
const code = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText
function api(options: { data?: any; attempt?: any; owner?: boolean; providerHttp?: number; malformed?: boolean } = {}) {
  let handler: any
  const requests: { url: string; init: RequestInit }[] = []
  const attempt = { id: 'attempt-id', payer_id: 'payer-id', escrow_id: 'escrow-id', mode: 'test', tx_ref: 'reference', currency: 'ETB', expected_amount_minor: 1000, status: 'pending', ...options.attempt }
  const fetch = vi.fn(async (url: string, init: RequestInit = {}) => {
    requests.push({ url, init })
    let body: any = []; let status = 200
    if (url.includes('/auth/v1/user')) body = { id: 'actor-id' }
    else if (url.includes('escrow_payment_attempts?') && !init.method) body = [attempt]
    else if (url.includes('escrow_transactions?')) body = [{ id: 'escrow-id', contract_id: 'contract-id' }]
    else if (url.includes('freelance_contracts?')) body = [{ id: 'contract-id', employer_id: 'employer-id' }]
    else if (url.includes('employers?')) body = [{ owner_id: options.owner === false ? 'other-id' : 'actor-id' }]
    else if (url.includes('profiles?')) body = [{ role: 'admin', account_status: 'active' }]
    else if (url.includes('api.chapa.co')) {
      status = options.providerHttp || 200
      body = options.malformed ? {} : { status: 'success', data: { status: 'success', amount: '10.00', currency: 'ETB', tx_ref: 'reference', reference: 'provider-ref', mode: 'test', ...options.data } }
    } else if (url.includes('rpc/finalize_escrow_payment')) body = { status: 'success' }
    return new Response(JSON.stringify(body), { status })
  })
  const env: Record<string, string> = { SUPABASE_URL: 'https://example.invalid', SUPABASE_ANON_KEY: 'test-public', SUPABASE_SERVICE_ROLE_KEY: 'test-service', CHAPA_SECRET_KEY: 'CHASECK_TEST_FAKE', MELA_PAYMENT_MODE: 'test' }
  new Function('Deno', 'fetch', code)({ env: { get: (key: string) => env[key] }, serve: (h: any) => { handler = h } }, fetch)
  return { requests, request: () => handler(new Request('https://example.invalid', { method: 'POST', headers: { Authorization: 'Bearer test-token', 'Content-Type': 'application/json' }, body: JSON.stringify({ action: 'verify_escrow', tx_ref: 'reference' }) })) }
}
const finalized = (server: ReturnType<typeof api>) => server.requests.some(r => r.url.includes('rpc/finalize_escrow_payment'))
describe('Manual escrow verification', () => {
  it('rejects unrelated employer access even when profile role is admin', async () => {
    const server = api({ owner: false }); expect((await server.request()).status).toBe(403)
    expect(server.requests.some(r => r.url.includes('api.chapa.co'))).toBe(false); expect(finalized(server)).toBe(false)
  })
  it('allows the original payer to verify their attempt', async () => {
    const server = api({ owner: false, attempt: { payer_id: 'actor-id' } }); expect((await server.request()).status).toBe(200); expect(finalized(server)).toBe(true)
  })
  it.each([{ amount: '10.001' }, { amount: '1e1' }, { amount: null }, { amount: '9.99' }, { currency: 'USD' }, { tx_ref: 'other' }, { mode: 'live' }, { reference: '' }])('does not finalize mismatched details %j', async data => {
    const server = api({ data }); const response = await server.request(); expect((await response.json()).status).toBe('mismatch'); expect(finalized(server)).toBe(false)
    const patch = server.requests.find(r => r.init.method === 'PATCH')!
    expect(patch.url).toContain('&status=in.(initiated,pending)'); expect(JSON.parse(String(patch.init.body)).status).toBeUndefined()
  })
  it('refuses cross-environment verification before provider access', async () => {
    const server = api({ attempt: { mode: 'live' } }); expect((await server.request()).status).toBe(409); expect(server.requests.some(r => r.url.includes('api.chapa.co'))).toBe(false)
  })
  it.each([404,429,500])('returns retryable failure for provider HTTP %s without overwriting state', async providerHttp => {
    const server = api({ providerHttp }); expect((await server.request()).status).toBe(503)
    expect(server.requests.some(r => r.init.method === 'PATCH')).toBe(false); expect(finalized(server)).toBe(false)
  })
  it('rejects an incomplete provider response', async () => {
    const server = api({ malformed: true }); expect((await server.request()).status).toBe(503); expect(finalized(server)).toBe(false)
  })
  it('restricts a delayed pending update to unfinished attempts', async () => {
    const server = api({ data: { status: 'pending' } }); await server.request()
    expect(server.requests.find(r => r.init.method === 'PATCH')?.url).toContain('&status=in.(initiated,pending)'); expect(finalized(server)).toBe(false)
  })
  it('acknowledges an already successful payment without provider access', async () => {
    const server = api({ attempt: { status: 'success' } }); expect((await server.request()).status).toBe(200)
    expect(server.requests.some(r => r.url.includes('api.chapa.co'))).toBe(false); expect(finalized(server)).toBe(false)
  })
  it('passes exact ETB minor units to the atomic finalizer', async () => {
    const server = api(); await server.request()
    const call = server.requests.find(r => r.url.includes('rpc/finalize_escrow_payment'))!
    expect(JSON.parse(String(call.init.body))).toMatchObject({ p_payment_id: 'attempt-id', p_provider_charge: 1000, p_provider_ref: 'provider-ref' })
  })
})
