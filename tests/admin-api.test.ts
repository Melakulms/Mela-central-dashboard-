import { readFileSync } from 'node:fs'
import ts from 'typescript'
import { describe, expect, it, vi } from 'vitest'

const source = readFileSync(new URL('../supabase/functions/mela-admin-api/index.ts', import.meta.url), 'utf8').replace(/^import .*\n/gm, '')
const code = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText

function server(permissions: string[], options: { user?: boolean; admin?: boolean; aal?: string; fixtures?: Record<string, object>; rpcError?: object } = {}) {
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
  const database: any = {
    rpc,
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
    () => calls++ % 2 === 0 ? caller : database,
  )
  const request = (body: unknown, authenticated = true, origin?:string) => handler!(new Request('https://example.invalid/admin', {
    method: 'POST', headers: { 'Content-Type': 'application/json', ...(origin?{Origin:origin}:{}), ...(authenticated ? { Authorization: 'Bearer test-token' } : {}) }, body: JSON.stringify(body),
  }))
  return { request, queried, ranges, filters, rpc, assurance: caller.auth.mfa.getAuthenticatorAssuranceLevel }
}

describe('Admin API security boundary', () => {
  it('allows GitHub Pages and rejects untrusted browser origins',async()=>{
    const response=await server([]).request({action:'me'},true,'https://melakulms.github.io')
    expect(response.status).toBe(200)
    expect(response.headers.get('Access-Control-Allow-Origin')).toBe('https://melakulms.github.io')
    expect((await server([]).request({action:'me'},true,'https://untrusted.invalid')).status).toBe(403)
  })
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
  it('uses one transactional RPC and reports rollback failures', async () => {
    const api = server(['finance.manage'], { rpcError: {code:'23514'}, fixtures: {
      invitation_commissions: { data: { id: 'commission-id', status: 'pending' }, error: null },
    } })
    const response = await api.request({ action: 'commission.cancel', commission_id: 'commission-id', reason: 'Regression test' })
    expect(response.status).toBe(500)
    expect((await response.json()).code).toBe('ADMIN_UPDATE_FAILED')
    expect(api.rpc).toHaveBeenCalledWith('apply_audited_update', expect.objectContaining({p_action:'commission.cancel',p_expected:{id:'commission-id',status:'pending'}}))
    expect(api.queried).not.toContain('audit_log')
  })
  it('rejects a decision made from a stale frontend record',async()=>{
    const api=server(['users.manage'],{fixtures:{profiles:{data:{id:'user-id',updated_at:'new-version'}}}})
    expect((await api.request({action:'user.update',user_id:'user-id',account_status:'suspended',expected_updated_at:'old-version'})).status).toBe(409)
    expect(api.rpc).not.toHaveBeenCalled()
  })
  it('requires a verification reason and management permission',async()=>{
    expect((await server(['users.read']).request({action:'employer.verify',employer_id:'company-id',verification_status:'verified',verification_notes:'Reviewed'})).status).toBe(403)
    expect((await server(['employers.manage']).request({action:'employer.verify',employer_id:'company-id',verification_status:'verified'})).status).toBe(400)
  })
  it('returns conflict when the locked record changed', async () => {
    const api = server(['users.manage'], {rpcError:{code:'40001'},fixtures:{profiles:{data:{id:'user-id',account_status:'active'}}}})
    expect((await api.request({action:'user.update',user_id:'user-id',account_status:'suspended'})).status).toBe(409)
  })
  it('rejects string booleans and statuses outside the live schema', async () => {
    const api = server(['users.manage'], {fixtures:{profiles:{data:{id:'user-id'}}}})
    expect((await api.request({action:'user.update',user_id:'user-id',email_verified:'false'})).status).toBe(400)
    expect((await api.request({action:'user.update',user_id:'user-id',account_status:'restricted'})).status).toBe(400)
    expect(api.rpc).not.toHaveBeenCalled()
  })
})

describe('Contract dispute inbox', () => {
  it('requires support permission before reading dispute records', async () => {
    const api=server(['dashboard.read'])
    expect((await api.request({action:'disputes.list'})).status).toBe(403)
    expect(api.queried).not.toContain('reports')
    expect(api.queried).not.toContain('freelance_contracts')
  })
  it('returns reports and held contracts to an MFA-verified support administrator', async () => {
    const api=server(['support.manage'],{fixtures:{reports:{data:[{id:'report'}]},freelance_contracts:{data:[{id:'contract',status:'disputed'}]}}})
    const response=await api.request({action:'disputes.list'})
    expect(response.status).toBe(200)
    expect(await response.json()).toEqual({reports:[{id:'report'}],contracts:[{id:'contract',status:'disputed'}]})
  })
})

describe('Moderation settlement safety', () => {
  it.each(['resolved','dismissed','reviewing'])('blocks generic %s decisions on contract disputes',async status=>{
    const api=server(['moderation.manage'],{fixtures:{reports:{data:{id:'report',status:'open',target_type:'freelance_contract',reason:'contract_dispute'}}}})
    const response=await api.request({action:'report.resolve',report_id:'report',status,resolution_notes:'Reviewed'})
    expect(response.status).toBe(409)
    expect((await response.json()).code).toBe('DISPUTE_SETTLEMENT_REQUIRED')
    expect(api.rpc).not.toHaveBeenCalled()
  })
  it('rejects closed reports and unexplained closure',async()=>{
    const closed=server(['moderation.manage'],{fixtures:{reports:{data:{id:'report',status:'resolved'}}}})
    expect((await closed.request({action:'report.resolve',report_id:'report',status:'reviewing'})).status).toBe(409)
    expect(closed.rpc).not.toHaveBeenCalled()
    const open=server(['moderation.manage'],{fixtures:{reports:{data:{id:'report',status:'open'}}}})
    expect((await open.request({action:'report.resolve',report_id:'report',status:'resolved'})).status).toBe(400)
    expect(open.rpc).not.toHaveBeenCalled()
    expect((await open.request({action:'report.resolve',report_id:'report',status:'resolved',resolution_notes:'Issue corrected'})).status).toBe(200)
    expect(open.rpc).toHaveBeenCalledOnce()
  })
  it('reports query failures instead of a false empty moderation queue',async()=>{
    const api=server(['moderation.manage'],{fixtures:{reports:{data:null,error:{message:'database unavailable'}}}})
    const response=await api.request({action:'moderation.list'})
    expect(response.status).toBe(500)
    expect((await response.json()).error).toContain('Moderation records unavailable')
  })
})

it('retains reviewing reports in both moderation queues',async()=>{
 const api=server(['moderation.manage','dashboard.read'])
 expect((await api.request({action:'moderation.list'})).status).toBe(200)
 expect(api.filters).toContainEqual(['status',['pending','open','review','reviewing','escalated']])
 api.filters.length=0
 expect((await api.request({action:'queues'})).status).toBe(200)
 expect(api.filters).toContainEqual(['status',['pending','open','review','reviewing','escalated']])
})

it('includes a user status-change reason in the atomic audit metadata',async()=>{
 const api=server(['users.manage'],{fixtures:{profiles:{data:{id:'user-id',account_status:'active',updated_at:'version'}}}});
 expect((await api.request({action:'user.update',user_id:'user-id',account_status:'suspended',expected_updated_at:'version',reason:'Confirmed moderation decision'})).status).toBe(200);
 expect(api.rpc.mock.calls[0][1].p_metadata.reason).toBe('Confirmed moderation decision');
});
it('rejects malformed review reasons before writes',async()=>{
 const api=server(['users.manage'],{fixtures:{profiles:{data:{id:'user-id',account_status:'active'}}}});
 expect((await api.request({action:'user.update',user_id:'user-id',account_status:'suspended',reason:{text:'wrong type'}})).status).toBe(400);expect(api.rpc).not.toHaveBeenCalled();
});
it('browses complete audit history with bounded pagination',async()=>{
 const api=server(['audit.read'],{fixtures:{audit_log:{data:[],count:600}}});const response=await api.request({action:'audit.list',offset:50,limit:25,search:'user.update'});
 expect(response.status).toBe(200);expect((await response.json()).total).toBe(600);expect(api.ranges).toContainEqual([50,74]);
});
