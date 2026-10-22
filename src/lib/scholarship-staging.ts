/**
 * Hard staging guard: never show scholarship write tools when the Admin app
 * is connected to the production Supabase project.
 */
export const STAGING_SUPABASE_URL = 'https://tungqfmypuwzeyrtaseh.supabase.co'

export function isScholarshipStagingUrl(url: string | undefined | null): boolean {
  return Boolean(url && url.trim().replace(/\/$/, '') === STAGING_SUPABASE_URL)
}

/**
 * Never persist reviewer sessions on the learner/admin shared GitHub Pages
 * origin, or on unknown/custom domains. Only an isolated Vercel preview origin
 * (or developer localhost) can store a tab-scoped staging session.
 */
export function canPersistStagingReviewerSession(supabaseUrl: string | undefined, browserOrigin: string): boolean {
  if (!isScholarshipStagingUrl(supabaseUrl)) return false
  return /^https:\/\/[a-z0-9-]+\.vercel\.app$/.test(browserOrigin)
    || /^http:\/\/localhost(?::[0-9]+)?$/.test(browserOrigin)
}
