import { describe, expect, it } from 'vitest'
import { isScholarshipStagingUrl, STAGING_SUPABASE_URL } from '../src/lib/scholarship-staging'

describe('staging-only scholarship UI', () => {
  it('allows staging and an optional trailing slash', () => {
    expect(isScholarshipStagingUrl(STAGING_SUPABASE_URL)).toBe(true)
    expect(isScholarshipStagingUrl(STAGING_SUPABASE_URL + '/')).toBe(true)
  })
  it('blocks production, unknown endpoints and unset environments', () => {
    expect(isScholarshipStagingUrl('https://duizgtmbptmlbyipreqg.supabase.co')).toBe(false)
    expect(isScholarshipStagingUrl(undefined)).toBe(false)
    expect(isScholarshipStagingUrl('')).toBe(false)
    expect(isScholarshipStagingUrl('https://tungqfmypuwzeyrtaseh.supabase.co.evil.example')).toBe(false)
  })
})
