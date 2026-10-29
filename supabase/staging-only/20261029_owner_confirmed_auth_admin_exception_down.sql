-- STAGING ONLY: revert the narrow confirmed-owner Auth Admin invitation gate.
-- The original registration trigger body remains otherwise unchanged.
DO $rollback$
DECLARE
  current_definition text;
  next_definition text;
BEGIN
  SELECT pg_get_functiondef('private.handle_new_auth_user()'::regprocedure)
    INTO current_definition;
  IF position('STAGING_CONFIRMED_OWNER_AUTH_ADMIN_ONLY_V1' in current_definition) = 0 THEN
    RAISE EXCEPTION 'Owner gate missing; cannot safely roll back';
  END IF;
  next_definition := replace(
    current_definition,
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
    or$replacement$,
    $needle$  if not public.platform_feature_available('registrations') and not ($needle$
  );
  IF next_definition = current_definition THEN
    RAISE EXCEPTION 'Owner gate not recognized; cannot safely roll back';
  END IF;
  EXECUTE next_definition;
  IF position('STAGING_CONFIRMED_OWNER_AUTH_ADMIN_ONLY_V1'
      in pg_get_functiondef('private.handle_new_auth_user()'::regprocedure)) > 0 THEN
    RAISE EXCEPTION 'Owner gate still present after rollback';
  END IF;
END;
$rollback$;
