/**
 * Hard staging guard: never show scholarship write tools when the Admin app
 * is connected to the production Supabase project.
 */
export const STAGING_SUPABASE_URL = 'https://tungqfmypuwzeyrtaseh.supabase.co'

export function isScholarshipStagingUrl(url: string | undefined | null): boolean {
  return Boolean(url && url.trim().replace(/\/$/, '') === STAGING_SUPABASE_URL)
}
