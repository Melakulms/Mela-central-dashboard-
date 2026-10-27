import { describe, expect, it } from 'vitest'
import { authorizeSection, canAccessSection, isProtectedSection } from '../src/lib/auth-route-guard'

describe('Central Admin mentorship review route', () => {
  it('requires the correct moderation permission; no general users gain access', () => {
    expect(isProtectedSection('mentorship')).toBe(true)
    expect(canAccessSection([], 'mentorship')).toBe(false)
    expect(canAccessSection(['content.manage'], 'mentorship')).toBe(false)
    expect(canAccessSection(['moderation.manage'], 'mentorship')).toBe(true)
    expect(canAccessSection(['*'], 'mentorship')).toBe(true)
  })
  it('keeps the authorization boundary for missing admin sign-in', () => {
    expect(authorizeSection(null,false,['moderation.manage'],'mentorship')).toMatchObject({
      allowed:false,reason:'AUTH_REQUIRED',
    })
  })
})
