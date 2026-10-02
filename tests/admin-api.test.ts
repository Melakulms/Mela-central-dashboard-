import { readFileSync } from 'node:fs'
import ts from 'typescript'
import { describe, expect, it, vi } from 'vitest'

const source = readFileSync(new URL('../supabase/functions/mela-admin-api/index.ts', import.meta.url), 'utf8').replace(/^import .*\n/gm, '')
const code = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText

function server(permissions: string[], options: { user?: boolean; admin?: boolean; aal?: string; fixtures?: Record<string, object> } = {}) {
  let handler: (request: Request) => Promise<Response>
  const queried: string[] = []
  const ranges: unknown[][] = []
  function query(result: object) {
    const builder: any = {}
    for (const method of ['select', 'eq', 'in', 'order', 'limit', 'gte', 'or']) builder[method] = () => builder
    builder.range = (...args: unknown[]) => { ranges.push(args); return builder }
    builder.update = () => builder
    builder.insert = () => Promise.resolve(result)
    builder.maybeSingle = builder.single = () => Promise.resolve(result)
    builder.then = (resolve: any, reject: any) => Promise.resolve(result).then(resolve, reject)
    return builder
  }
  const caller = { auth: {
    getUser: vi.fn().mockResolvedValue({ data: { user: options.user === false ? null : { id: 'admin-id' } }, error: null }),
    mfa: { getAuthenticatorAssuranceLevel: vi.fn().mockResolvedValue({ data: { currentLevel: options.aal ?? 'aal2' } }) },
  } }
  const database: any = {
    schema: () => database,
    from: (table: string) => {
      queried.push(table)
      const results: Record<string, object> = {
        admin_users: { data: options.admin === false ? null : { role_id: 'role-id', mfa_required: true } },
        roles: { data: { key: 'limited-admin', name: 'Limited administrator' } },
        role_permissions: { data: [{ permission_id: 'permission-id' }] },
        permissions: { data: permissions.map(key => ({ key })) },
      }
      return query(options.fixtures?.[table] ?? results[table] ?? { data: [], count: 0, error: null })
    },
  }
  let calls = 0
  new Function('Deno', 'createClient', code)(
    { env: { get: () => 'test-config' }, serve: (callback: typeof handler) => { handler = callback } },
    () => calls++ === 0 ? caller : database,
  )
  const request = (body: unknown, authenticated = true) => handler!(new Request('https://example.invalid/admin', {
    method: 'POST', headers: { 'Content-Type': 'application/json', ...(authenticated ? { Authorization: 'Bearer test-token' } : {}) }, body: JSON.stringify(body),
  }))
  return { request, queried, ranges, assurance: caller.auth.mfa.getAuthenticatorAssuranceLevel }
}

describe('Admin API security boundary', () => {
  it('rejects requests without an authenticated session', async () => {
    expect((await server([]).request({ action: 'me' }, false)).status).toBe(401)
    expect((await server([], { user: false }).request({ action: 'me' })).status).toBe(401)
  })
  it('checks MFA against the authenticated bearer token', async () => {
    const api = server([])
    await api.request({ action: 'me' })
    expect(api.assurance).toHaveBeenCalledWith('test-token')
  })
  it('requires active admin membership and MFA', async () => {
    expect((await server(['*'], { admin: false }).request({ action: 'me' })).status).toBe(403)
    const response = await server(['users.read'], { aal: 'aal1' }).request({ action: 'users.list' })
    expect(response.status).toBe(403)
    expect((await response.json()).code).toBe('MFA_REQUIRED')
  })
  it('rejects malformed JSON shapes and missing actions', async () => {
    expect((await server([]).request([])).status).toBe(400)
    expect((await server([]).request({})).status).toBe(400)
  })
  it('keeps financial records out of a dashboard-only role', async () => {
    const api = server(['dashboard.read'])
    const response = await api.request({ action: 'queues' })
    expect(response.status).toBe(200)
    expect(api.queried).not.toContain('payout_requests')
    expect(api.queried).not.toContain('employer_registration_requests')
    expect(await response.json()).toEqual({})
  })
  it('denies financial access to an ordinary user reader', async () => {
    expect((await server(['users.read']).request({ action: 'payments.list' })).status).toBe(403)
  })
  it('bounds invalid pagination and prevents response caching', async () => {
    const api = server(['users.read'])
    const response = await api.request({ action: 'users.list', limit: 'Infinity', offset: 'invalid' })
    expect(response.status).toBe(200)
    expect(api.ranges).toEqual([[0, 49]])
    expect(response.headers.get('Cache-Control')).toBe('no-store')
  })
  it('reports audit persistence failures instead of returning success after a mutation', async () => {
    const api = server(['finance.manage'], { fixtures: {
      invitation_commissions: { data: { id: 'commission-id', status: 'pending' }, error: null },
      audit_log: { error: new Error('Audit database unavailable') },
    } })
    const response = await api.request({ action: 'commission.cancel', commission_id: 'commission-id', reason: 'Regression test' })
    expect(response.status).toBe(500)
    const body = await response.json()
    expect(body.code).toBe('AUDIT_WRITE_FAILED')
    expect(body.error).toContain('Do not repeat')
  })
})
