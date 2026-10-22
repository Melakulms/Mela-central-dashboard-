import { readFileSync } from 'node:fs'
import { describe, it, expect } from 'vitest'

const yaml = readFileSync(new URL('../render.yaml', import.meta.url), 'utf8')

describe('Render staging scholarship static site configuration', () => {
  it('deploys only the staging branch as a static site without automatic deploys', () => {
    expect(yaml).toMatch(/runtime:\s*static/)
    expect(yaml).toMatch(/name:\s*mela-scholarship-admin-staging/)
    expect(yaml).toMatch(/branch:\s*staging\/scholarship-access-20261021/)
    expect(yaml).toMatch(/autoDeployTrigger:\s*["']?off/)
    expect(yaml).toMatch(/staticPublishPath:\s*\.\/dist/)
    expect(yaml).toMatch(/buildCommand:\s*npm ci && npm run build/)
  })
  it('targets only MELA staging and never contains privileged keys', () => {
    expect(yaml).toContain('https://tungqfmypuwzeyrtaseh.supabase.co')
    expect(yaml).not.toContain('duizgtmbptmlbyipreqg')
    expect(yaml).toContain('VITE_SUPABASE_PUBLISHABLE_KEY')
    expect(yaml).not.toMatch(/service.?role|sb_secret_|payment_collection_enabled/i)
  })
  it('provides SPA fallback and disallows indexing or frame embedding', () => {
    expect(yaml).toMatch(/type:\s*rewrite/)
    expect(yaml).toContain('/index.html')
    expect(yaml).toContain('X-Robots-Tag')
    expect(yaml).toContain('X-Frame-Options')
    expect(yaml).toContain('no-store')
  })
})
