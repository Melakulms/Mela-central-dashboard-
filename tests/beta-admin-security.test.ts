import { readFileSync } from 'node:fs'
import ts from 'typescript'
import { describe, expect, it, vi } from 'vitest'

const source = readFileSync(new URL('../supabase/functions/mela-beta-admin/index.ts', import.meta.url), 'utf8').replace(/^import .*\n/gm, '')
const code = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText

function server(permissions: string[], options: { user?: boolean; admin?: boolean; aal?: string; fixtures?: Record<string, object>; rpcError?: object; actorProfile?: object | null; actorError?: object; mfaRequired?: boolean } = {}) {
  let handler: (request: Request) => Promise<Response>
  const queried: string[] = []
  const ranges: unknown[][] = []
  const filters: unknown[][] = []
  function query(result: object) {
    const builder: any = {}
    for (const method of ['select', 'eq', 'in', 'order', 'limit', 'gte', 'or', 'ilike']) builder[method] = () => builder
    builder.in = (...args: unknown[]) => { filters.push(args); return builder }
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
  const rpc = vi.fn().mockResolvedValue({data: {id: "updated-id"}, error: options.rpcError ?? null})
  let profileReads = 0
  const database: any = {
    rpc,
    schema: () => database,
    from: (table: string) => {
      queried.push(table)
      if (table === 'profiles' && profileReads++ === 0) return query({data: options.actorProfile === undefined ? {account_status: 'active', deleted_at: null} : options.actorProfile, error: options.actorError ?? null})
      const results: Record<string, object> = {
        admin_users: { data: options.admin === false ? null : { role_id: 'role-id', mfa_required: options.mfaRequired ?? true } },
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
    () => calls++ % 2 === 0 ? caller : database,
  )
  const request = (body: unknown, authenticated = true, origin?:string) => { profileReads = 0; return handler!(new Request('https://example.invalid/admin', {
    method: 'POST', headers: { 'Content-Type': 'application/json', ...(origin?{Origin:origin}:{}), ...(authenticated ? { Authorization: 'Bearer test-token' } : {}) }, body: JSON.stringify(body),
  })) }
  return { request, queried, ranges, filters, rpc, assurance: caller.auth.mfa.getAuthenticatorAssuranceLevel }
}

describe('Beta invitation administration authorization', () => {
  it('allows active authorized administrators with MFA to list invitations', async () => {
    const api=server(['users.manage'])
    expect((await api.request({action:'invite.list'})).status).toBe(200)
    expect(api.queried).toContain('beta_access_invites')
  })
  it.each(['suspended','banned','deleted'])('rejects %s administrators before reading invitations',async status=>{
    const api=server(['users.manage'],{actorProfile:{account_status:status,deleted_at:null}})
    expect((await api.request({action:'invite.list'})).status).toBe(403)
    expect(api.queried).not.toContain('beta_access_invites')
  })
  it('requires MFA even when the legacy flag is false',async()=>{
    const api=server(['users.manage'],{aal:'aal1',mfaRequired:false})
    expect((await api.request({action:'invite.list'})).status).toBe(403)
    expect(api.queried).not.toContain('beta_access_invites')
  })
  it('fails closed for missing or deleted profiles and lookup failures',async()=>{
    for(const actorProfile of [null,{account_status:'active',deleted_at:'2026-10-14'}]) {
      expect((await server(['users.manage'],{actorProfile}).request({action:'invite.list'})).status).toBe(403)
    }
    expect((await server(['users.manage'],{actorError:{message:'unavailable'}}).request({action:'invite.list'})).status).toBe(503)
  })
  it('rejects ordinary users and administrators without user management permission',async()=>{
    expect((await server(['users.manage'],{admin:false}).request({action:'invite.list'})).status).toBe(403)
    expect((await server(['users.read']).request({action:'invite.list'})).status).toBe(403)
  })
})
