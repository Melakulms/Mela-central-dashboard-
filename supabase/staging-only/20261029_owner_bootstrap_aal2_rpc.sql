-- STAGING ONLY: tungqfmypuwzeyrtaseh.
-- Invoked by an authenticated, confirmed, AAL2 owner after private sign-in.
-- The existing admin.bootstrap_first_super_admin() performs the authoritative
-- owner-email/verified-email/MFA/one-use checks and writes the audit record.
-- No rows or administrative memberships are inserted by this migration.
CREATE OR REPLACE FUNCTION public.claim_staging_first_super_admin()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $body$
DECLARE
  claims jsonb := auth.jwt();
BEGIN
  -- Project pin: never allow this endpoint to work with another Supabase JWT.
  IF COALESCE(claims ->> 'iss', '') <> 'https://tungqfmypuwzeyrtaseh.supabase.co/auth/v1' THEN
    RETURN pg_catalog.jsonb_build_object('success', false, 'code', 'staging_session_required');
  END IF;
  IF auth.uid() IS NULL OR COALESCE(claims ->> 'aal', '') <> 'aal2' THEN
    RETURN pg_catalog.jsonb_build_object('success', false, 'code', 'mfa_required');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.platform_feature_flags
    WHERE feature_key = 'staging_beta_invites' AND enabled IS TRUE
  ) THEN
    RETURN pg_catalog.jsonb_build_object('success', false, 'code', 'staging_only');
  END IF;
  RETURN admin.bootstrap_first_super_admin();
END;
$body$;

REVOKE ALL ON FUNCTION public.claim_staging_first_super_admin() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.claim_staging_first_super_admin() FROM anon;
REVOKE ALL ON FUNCTION public.claim_staging_first_super_admin() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.claim_staging_first_super_admin() TO authenticated;

DO $verify$
BEGIN
  IF has_function_privilege('anon','public.claim_staging_first_super_admin()','EXECUTE')
      OR NOT has_function_privilege('authenticated','public.claim_staging_first_super_admin()','EXECUTE')
  THEN RAISE EXCEPTION 'Unsafe staging bootstrap RPC privileges'; END IF;
  IF EXISTS (SELECT 1 FROM admin.admin_users)
  THEN RAISE EXCEPTION 'An administrator already exists; no bootstrap RPC installation allowed'; END IF;
  IF NOT EXISTS (SELECT 1 FROM admin.bootstrap_state WHERE id = true AND consumed_at IS NULL AND consumed_by IS NULL)
  THEN RAISE EXCEPTION 'One-use bootstrap lock missing or consumed'; END IF;
END;
$verify$;
