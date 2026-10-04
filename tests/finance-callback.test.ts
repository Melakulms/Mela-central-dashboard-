import { readFileSync } from 'node:fs'
import { createHmac, webcrypto } from 'node:crypto'
import ts from 'typescript'
import { describe, it, expect, vi } from 'vitest'

const source = readFileSync(new URL('../supabase/functions/mela-finance-callback/index.ts', import.meta.url), 'utf8').replace(/^import .*\n/gm, '')
const code = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText
const webhookSecret = 'local-test-webhook-secret'
function api(options: { mode?: string; attempt?: any; data?: any; providerHttp?: number; signature?: string; secret?: string; idempotent?: boolean } = {}) {
  let handler: (request: Request) => Promise<Response>
  const mode = options.mode || 'test'
  const attempt = { id: 'attempt-id', escrow_id: 'escrow-id', tx_ref: 'reference', expected_amount_minor: 1000, currency: 'ETB', mode, status: 'pending', ...options.attempt }
  const requests: { url: string; init: RequestInit }[] = []
  const fetch = vi.fn(async (url: string, init: RequestInit = {}) => {
    requests.push({ url, init })
    let body: any = null
    let status = 200
    if (url.includes('escrow_payment_attempts?') && !init.method) body = [attempt]
    else if (url.includes('api.chapa.co')) {
      status = options.providerHttp || 200
      body = { status: 'success', data: { status: 'success', tx_ref: 'reference', amount: '10.00', currency: 'ETB', mode, reference: 'provider-reference', ...options.data } }
    } else if (url.includes('rpc/finalize_escrow_payment')) body = { idempotent: options.idempotent === true, escrow_id: 'escrow-id' }
    else if (url.includes('escrow_transactions?')) body = [{ id: 'escrow-id', user_id: 'student-id' }]
    return new Response(JSON.stringify(body), { status })
  })
  const environment: Record<string, string> = { SUPABASE_URL: 'https://example.invalid', SUPABASE_SERVICE_ROLE_KEY: 'fake-local-service-key', CHAPA_WEBHOOK_SECRET: options.secret ?? webhookSecret, CHAPA_SECRET_KEY: mode === 'test' ? 'CHASECK_TEST_FAKE' : 'CHASECK_FAKE', MELA_PAYMENT_MODE: mode }
  new Function('Deno', 'fetch', 'crypto', code)({ env: { get: (name: string) => environment[name] }, serve: (value: typeof handler) => { handler = value } }, fetch, webcrypto)
  return {
    requests,
    async request(body = JSON.stringify({ tx_ref: 'reference' })) {
      const signature = options.signature ?? createHmac('sha256', webhookSecret).update(body).digest('hex')
      return handler(new Request('https://example.invalid', { method: 'POST', headers: { 'x-chapa-signature': signature }, body }))
    },
  }
}
const finalized = (server: ReturnType<typeof api>) => server.requests.some(request => request.url.includes('rpc/finalize_escrow_payment'))

describe('Escrow callback boundary', () => {
  it('rejects an unsigned request before database/provider access', async () => {
    const server = api({ signature: '' }); expect((await server.request()).status).toBe(401); expect(server.requests).toHaveLength(0)
  })
  it('fails closed when webhook verification is not configured', async () => {
    const server = api({ secret: '' }); expect((await server.request()).status).toBe(503); expect(server.requests).toHaveLength(0)
  })
  it('rejects a signature copied onto a different body', async () => {
    const signature = createHmac('sha256', webhookSecret).update('{"tx_ref":"another"}').digest('hex')
    const server = api({ signature }); expect((await server.request()).status).toBe(401); expect(server.requests).toHaveLength(0)
  })
  it.each([
    { mode: 'test' }, { amount: '10.001' }, { amount: null }, { amount: '1e1' },
    { amount: '9007199254740992' }, { amount: '9.99' }, { currency: 'USD' },
    { tx_ref: 'different' }, { reference: '' },
  ])('rejects mismatched or invalid provider details: %j', async data => {
    const server = api({ mode: 'live', data }); expect((await server.request()).status).toBe(409); expect(finalized(server)).toBe(false)
  })
  it('rejects an attempt from a different environment before contacting provider', async () => {
    const server = api({ mode: 'live', attempt: { mode: 'test' } }); expect((await server.request()).status).toBe(409)
    expect(server.requests.some(request => request.url.includes('api.chapa.co'))).toBe(false)
  })
  it('returns retryable status when the provider is unavailable', async () => {
    const server = api({ providerHttp: 503 }); expect((await server.request()).status).toBe(503); expect(finalized(server)).toBe(false)
  })
  it('acknowledges a replay without re-verifying or notifying', async () => {
    const server = api({ attempt: { status: 'success' } }); expect((await server.request()).status).toBe(200)
    expect(server.requests).toHaveLength(1)
  })
  it('only updates unfinished attempts when a delayed result is pending', async () => {
    const server = api({ data: { status: 'pending' } }); await server.request()
    const patch = server.requests.find(request => request.init.method === 'PATCH')
    expect(patch?.url).toContain('&status=in.(initiated,pending)'); expect(finalized(server)).toBe(false)
  })
  it('finalizes a verified exact ETB amount through the atomic database function', async () => {
    const server = api(); expect((await server.request()).status).toBe(200)
    const request = server.requests.find(request => request.url.includes('rpc/finalize_escrow_payment'))!
    expect(JSON.parse(String(request.init.body))).toMatchObject({ p_payment_id: 'attempt-id', p_provider_charge: 1000, p_provider_ref: 'provider-reference' })
  })
  it('does not repeat notification when concurrent finalization reports an idempotent result', async () => {
    const server = api({ idempotent: true }); expect((await server.request()).status).toBe(200); expect(finalized(server)).toBe(true)
    expect(server.requests.some(request => request.url.includes('notifications'))).toBe(false)
  })
  it('rejects malformed signed JSON before database access', async () => {
    const server = api(); expect((await server.request('{')).status).toBe(400); expect(server.requests).toHaveLength(0)
  })
})
