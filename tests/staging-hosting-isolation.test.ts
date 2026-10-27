import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

const stagingHost = 'tungqfmypuwzeyrtaseh.supabase.co'
const productionHost = 'duizgtmbptmlbyipreqg.supabase.co'
const vercel = JSON.parse(readFileSync(new URL('../vercel.json', import.meta.url), 'utf8'))
const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8')
const adminClient = readFileSync(new URL('../src/lib/admin-api.ts', import.meta.url), 'utf8')

describe('staging Central Admin origin isolation', () => {
  it('limits both server and HTML CSP connection endpoints to staging', () => {
    const policy = vercel.headers.find((entry: { source: string }) => entry.source === '/(.*)').headers
    const csp = policy.find((header: { key: string }) => header.key === 'Content-Security-Policy').value as string
    expect(csp).toContain('https://' + stagingHost)
    expect(csp).toContain('wss://' + stagingHost)
    expect(csp).not.toContain(productionHost)
    expect(html).toContain('https://' + stagingHost)
    expect(html).not.toContain(productionHost)
  })

  it('fails closed before signing in if a Vercel preview points to another Supabase project', () => {
    expect(adminClient).toContain("url !== 'https://" + stagingHost + "'")
    expect(adminClient).toContain("key.startsWith('sb_publishable_')")
  })
})
