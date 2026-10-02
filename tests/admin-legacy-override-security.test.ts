import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

const migration = readFileSync(
  new URL('../supabase/migrations/20261002231500_harden_legacy_admin_override.sql', import.meta.url),
  'utf8',
)

const finance = readFileSync(
  new URL('../supabase/functions/mela-finance/index.ts', import.meta.url),
  'utf8',
)

describe('legacy privileged-path hardening', () => {
  it('binds the broad database admin override to central super-admin membership and MFA', () => {
    expect(migration).toContain('join admin.admin_users au')
    expect(migration).toContain("ar.key = 'super_admin'")
    expect(migration).toContain("auth.jwt() ->> 'aal'")
    expect(migration).toContain("= 'aal2'")
  })

  it('does not let the finance Edge Function authorize from profiles.role=admin', () => {
    expect(finance).not.toMatch(/role\s*={2,3}\s*['"]admin['"]|role='admin'/)
    expect(finance).not.toContain('async function isAdmin')
    expect(finance).toContain('employer_members?employer_id=eq.')
  })
})
