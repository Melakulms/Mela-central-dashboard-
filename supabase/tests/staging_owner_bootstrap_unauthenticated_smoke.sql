-- Staging-only, no credentials: verify bootstrap gate denies anonymous access
-- and no-JWT authenticated connections. Does not create or promote any account.
DO $check$
DECLARE fn_definition text;
BEGIN
  IF has_function_privilege('anon','public.claim_staging_first_super_admin()','EXECUTE')
  THEN RAISE EXCEPTION 'Anonymous role can execute first-admin bootstrap'; END IF;
  IF NOT has_function_privilege('authenticated','public.claim_staging_first_super_admin()','EXECUTE')
  THEN RAISE EXCEPTION 'Authenticated staging owner cannot invoke bootstrap'; END IF;
  SELECT pg_get_functiondef('public.claim_staging_first_super_admin()'::regprocedure)
    INTO fn_definition;
  IF position('tungqfmypuwzeyrtaseh.supabase.co/auth/v1' in fn_definition)=0
    OR position('admin.bootstrap_first_super_admin()' in fn_definition)=0
    OR position('aal2' in fn_definition)=0
  THEN RAISE EXCEPTION 'Bootstrap no longer pins staging issuer, AAL2 and audited owner function'; END IF;
  IF public.platform_feature_available('registrations')
  THEN RAISE EXCEPTION 'Public registration unexpectedly active'; END IF;
  IF position('STAGING_CONFIRMED_OWNER_AUTH_ADMIN_ONLY_V1'
      in pg_get_functiondef('private.handle_new_auth_user()'::regprocedure))=0
    OR position('STAGING_CONFIRMED_OWNER_ACTIVE_PROFILE_V1'
      in pg_get_functiondef('private.handle_new_auth_user()'::regprocedure))=0
  THEN RAISE EXCEPTION 'Narrow owner-registration guard missing'; END IF;
END;
$check$;

BEGIN;
SET LOCAL ROLE authenticated;
DO $no_jwt$
DECLARE result jsonb;
BEGIN
  result := public.claim_staging_first_super_admin();
  IF result IS NULL OR result->>'success' <> 'false'
    OR result->>'code' <> 'staging_session_required' THEN
    RAISE EXCEPTION 'No-JWT authenticated session unexpectedly passed bootstrap';
  END IF;
END;
$no_jwt$;
ROLLBACK;

BEGIN;
SET LOCAL ROLE anon;
DO $anon$
DECLARE blocked boolean := false;
BEGIN
  BEGIN
    PERFORM public.claim_staging_first_super_admin();
  EXCEPTION WHEN insufficient_privilege THEN
    blocked := true;
  END;
  IF NOT blocked THEN
    RAISE EXCEPTION 'Anonymous caller was not denied by EXECUTE privilege';
  END IF;
END;
$anon$;
ROLLBACK;
SELECT 'owner_bootstrap_unauthenticated_security_passed' AS result;
