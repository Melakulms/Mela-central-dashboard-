import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

const source = readFileSync(new URL('../src/lib/admin-api.ts', import.meta.url), 'utf8')

describe('admin browser session hardening', () => {
  it('does not persist the privileged session in origin-wide browser storage', () => {
    expect(source).toMatch(/persistSession:\s*false/)
    expect(source).toMatch(/detectSessionInUrl:\s*false/)
    expect(source).not.toContain("storageKey: 'mela-central-admin-auth'")
  })

  it('removes credentials persisted by older admin builds', () => {
    expect(source).toContain("const LEGACY_ADMIN_STORAGE_KEY = 'mela-central-admin-auth'")
    expect(source).toContain('window.localStorage.removeItem(LEGACY_ADMIN_STORAGE_KEY)')
  })
})
