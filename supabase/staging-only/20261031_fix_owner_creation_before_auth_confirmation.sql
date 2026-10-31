-- STAGING ONLY: user-creation compatibility for the designated first owner.
-- The Auth Admin create-user operation may set email_confirmed_at *after*
-- the initial auth.users INSERT. The old exception demanded confirmation
-- during the INSERT, causing SQLSTATE P0001 / "Database error creating user."
--
-- This patch changes only the INSERT registration guard:
--  * allow ONLY the designated first-owner email while bootstrap is unused
--  * the owner account is NOT considered confirmed or admin by this allowance
--  * the profile remains pending_verification until Supabase Auth confirms it
--  * existing auth.users -> profiles confirmation sync updates it to active
--  * admin.bootstrap_first_super_admin independently requires confirmed email,
--    AAL2/MFA and the owner-email match; no role is assigned by this patch
--  * all other registration rules remain untouched; production must not apply
DO $staging_owner_guard$
DECLARE
  prior_definition text;
  revised_definition text;
  old_guard text := $old$
    /* STAGING_CONFIRMED_OWNER_AUTH_ADMIN_ONLY_V1 */
    (
      lower(coalesce(new.email, '')) = 'melakuanteneh1@gmail.com'
      and new.email_confirmed_at is not null
      and new.is_anonymous is false$old$;
  new_guard text := $new$
    /* STAGING_OWNER_TWO_PHASE_AUTH_CREATION_V2 */
    (
      lower(coalesce(new.email, '')) = 'melakuanteneh1@gmail.com'
      and new.is_anonymous is false$new$;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.platform_feature_flags
    WHERE feature_key='staging_beta_invites' AND enabled IS TRUE) THEN
    RAISE EXCEPTION 'STAGING ONLY: missing staging marker';
  END IF;
  IF EXISTS (SELECT 1 FROM admin.admin_users)
     OR NOT EXISTS (SELECT 1 FROM admin.bootstrap_state
       WHERE id=true AND consumed_at IS NULL AND consumed_by IS NULL) THEN
    RAISE EXCEPTION 'First-admin lock unavailable or administrator already exists';
  END IF;
  SELECT pg_catalog.pg_get_functiondef('private.handle_new_auth_user()'::pg_catalog.regprocedure)
    INTO prior_definition;
  IF pg_catalog.strpos(prior_definition,'STAGING_CONFIRMED_OWNER_ACTIVE_PROFILE_V1')=0
     OR pg_catalog.strpos(prior_definition,old_guard)=0
     OR pg_catalog.strpos(prior_definition,'STAGING_OWNER_TWO_PHASE_AUTH_CREATION_V2')>0 THEN
    RAISE EXCEPTION 'Registration function changed; reject this patch';
  END IF;
  revised_definition := pg_catalog.replace(prior_definition,old_guard,new_guard);
  IF pg_catalog.strpos(revised_definition,old_guard)>0
    OR pg_catalog.strpos(revised_definition,'new.email_confirmed_at is not null')=0
    OR pg_catalog.strpos(revised_definition,'Mela registrations are temporarily disabled')=0 THEN
    RAISE EXCEPTION 'Unexpected guard transformation';
  END IF;
  EXECUTE revised_definition;
END;
$staging_owner_guard$;