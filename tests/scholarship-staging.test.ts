import { describe, expect, it } from 'vitest'
import { isScholarshipStagingUrl, canPersistStagingReviewerSession, STAGING_SUPABASE_URL } from '../src/lib/scholarship-staging'

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

describe('staging-only reviewer tab persistence', () => {
  it('allows only an isolated preview or localhost for the staging project', () => {
    expect(canPersistStagingReviewerSession(STAGING_SUPABASE_URL, 'https://mela-scholarship-preview.vercel.app')).toBe(true)
    expect(canPersistStagingReviewerSession(STAGING_SUPABASE_URL, 'https://mela-scholarship-admin-staging.onrender.com')).toBe(true)
    expect(canPersistStagingReviewerSession(STAGING_SUPABASE_URL, 'https://mela-scholarship-admin-staging-2.onrender.com')).toBe(true)
    expect(canPersistStagingReviewerSession(STAGING_SUPABASE_URL, 'https://other-project.onrender.com')).toBe(false)
    expect(canPersistStagingReviewerSession(STAGING_SUPABASE_URL, 'https://mela-scholarship-admin-staging.onrender.com.evil.example')).toBe(false)
    expect(canPersistStagingReviewerSession(STAGING_SUPABASE_URL, 'http://localhost:5173')).toBe(true)
    expect(canPersistStagingReviewerSession(STAGING_SUPABASE_URL, 'https://melakulms.github.io')).toBe(false)
    expect(canPersistStagingReviewerSession(STAGING_SUPABASE_URL, 'https://other.example.com')).toBe(false)
    expect(canPersistStagingReviewerSession('https://duizgtmbptmlbyipreqg.supabase.co','https://mela-scholarship-preview.vercel.app')).toBe(false)
    expect(canPersistStagingReviewerSession(STAGING_SUPABASE_URL, 'https://preview.vercel.app.evil.example')).toBe(false)
  })
})
