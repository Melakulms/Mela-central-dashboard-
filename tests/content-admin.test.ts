import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

const source = readFileSync(new URL('../supabase/functions/mela-content-admin/index.ts', import.meta.url), 'utf8')
const migration = readFileSync(new URL('../supabase/migrations/20261005065833_phase8_content_studio_foundation.sql', import.meta.url), 'utf8')

function compact(value: string) {
  return value.replace(/\s+/g, ' ')
}

describe('Phase 8 content admin safety contract', () => {
  it('requires authenticated MFA-backed admin content permission', () => {
    expect(source).toContain("authHeader?.startsWith('Bearer ')")
    expect(source).toContain("assurance?.currentLevel !== 'aal2'")
    expect(source).toContain("permissions.includes('content.manage')")
    expect(source).toContain(".eq('active', true).maybeSingle()")
  })

  it('does not expose an administrative publish or approve action', () => {
    expect(source).not.toContain("action === 'draft.publish'")
    expect(source).not.toContain("action === 'draft.approve'")
    expect(source).toContain('publication_locked: true')
    expect(source).toContain('qualified review evidence exists')
  })

  it('uses optimistic version checks and immutable snapshots', () => {
    expect(source).toContain("code: 'STALE_DRAFT'")
    expect(source).toContain(".eq('version', existing.version)")
    expect(migration).toContain('admin.content_draft_versions')
    expect(migration).toContain('unique (draft_id, version_no)')
    expect(migration).toContain('new.version := old.version + 1')
  })

  it('prevents browser roles from directly accessing draft storage', () => {
    const sql = compact(migration)
    expect(sql).toContain('revoke all on admin.content_drafts from public, anon, authenticated;')
    expect(sql).toContain('revoke all on admin.content_draft_versions from public, anon, authenticated;')
    expect(sql).toContain('grant select, insert, update on admin.content_drafts to service_role;')
  })

  it('uses security-invoker inventory views and keeps qualified review counts visible', () => {
    expect(migration.match(/with \(security_invoker = true\)/g)?.length).toBe(3)
    expect(migration).toContain("validation_status='educator_verified'")
    expect(migration).toContain("status='approved'")
    expect(migration).toContain("status in ('pending','in_review','submitted')")
  })
})
