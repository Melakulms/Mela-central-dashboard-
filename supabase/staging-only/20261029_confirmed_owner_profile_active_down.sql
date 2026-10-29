-- Staging-only guarded removal of the confirmed-owner active-profile exception.
DO $rollback$
DECLARE original text; revised text;
BEGIN
 SELECT pg_get_functiondef('private.handle_new_auth_user()'::regprocedure) INTO original;
 IF position('STAGING_CONFIRMED_OWNER_ACTIVE_PROFILE_V1' in original)=0
 THEN RAISE EXCEPTION 'Expected owner active-profile rule missing'; END IF;
 revised := replace(original,$replacement$   case
     /* STAGING_CONFIRMED_OWNER_ACTIVE_PROFILE_V1 */
     when lower(coalesce(new.email, '')) = 'melakuanteneh1@gmail.com'
       and new.email_confirmed_at is not null
       and new.is_anonymous is false
       and exists (
         select 1 from admin.bootstrap_state b
         where b.id is true and b.consumed_at is null and b.consumed_by is null
       )
       and not exists (select 1 from admin.admin_users)
       then 'active'
     when new.raw_app_meta_data->>'mela_staging_invited'='true'
     and new.raw_user_meta_data->>'test_account'='true'$replacement$,$needle$   case when new.raw_app_meta_data->>'mela_staging_invited'='true'
     and new.raw_user_meta_data->>'test_account'='true'$needle$);
 IF revised=original THEN RAISE EXCEPTION 'Active profile rule changed; refuse rollback'; END IF;
 EXECUTE revised;
 IF position('STAGING_CONFIRMED_OWNER_ACTIVE_PROFILE_V1' in pg_get_functiondef('private.handle_new_auth_user()'::regprocedure))>0
 THEN RAISE EXCEPTION 'Owner rule still present'; END IF;
END;
$rollback$;
