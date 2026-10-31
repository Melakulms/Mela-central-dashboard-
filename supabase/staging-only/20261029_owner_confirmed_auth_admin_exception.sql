-- STAGING ONLY: permit Auth Admin creation of a PRE-CONFIRMED designated owner,
-- without lifting the registration block for public signups.
-- Confirmed email is a server-maintained Auth field, not user_metadata.
DO $apply$
DECLARE
  current_definition text;
  next_definition text;
BEGIN
  SELECT pg_get_functiondef('private.handle_new_auth_user()'::regprocedure)
    INTO current_definition;
  IF position('STAGING_CONFIRMED_OWNER_AUTH_ADMIN_ONLY_V1' in current_definition) > 0 THEN
    RAISE EXCEPTION 'Staging owner exception already installed';
  END IF;
  IF position($needle$  if not public.platform_feature_available('registrations') and not ($needle$ in current_definition) = 0 THEN
    RAISE EXCEPTION 'Auth registration trigger has changed; manual review required';
  END IF;
  next_definition := replace(
    current_definition,
    $needle$  if not public.platform_feature_available('registrations') and not ($needle$,
    $replacement$  if not public.platform_feature_available('registrations') and not (
    /* STAGING_CONFIRMED_OWNER_AUTH_ADMIN_ONLY_V1 */
    (
      lower(coalesce(new.email, '')) = 'melakuanteneh1@gmail.com'
      and new.email_confirmed_at is not null
      and new.is_anonymous is false
      and exists (
        select 1 from admin.bootstrap_state b
        where b.id is true and b.consumed_at is null and b.consumed_by is null
      )
      and not exists (select 1 from admin.admin_users)
    )
    or$replacement$
  );
  EXECUTE next_definition;
  IF position('STAGING_CONFIRMED_OWNER_AUTH_ADMIN_ONLY_V1'
      in pg_get_functiondef('private.handle_new_auth_user()'::regprocedure)) = 0 THEN
    RAISE EXCEPTION 'Staging owner exception did not apply';
  END IF;
END;
$apply$;
