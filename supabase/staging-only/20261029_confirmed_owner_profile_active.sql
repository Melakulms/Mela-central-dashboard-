-- Staging only. The Auth Admin-created, already-confirmed designated owner
-- must have an active profile for admin API membership checks after AAL2 setup.
-- Ordinary public signups and all other users retain existing status logic.
DO $apply$
DECLARE original text; revised text;
BEGIN
 SELECT pg_get_functiondef('private.handle_new_auth_user()'::regprocedure) INTO original;
 IF position('STAGING_CONFIRMED_OWNER_AUTH_ADMIN_ONLY_V1' in original) = 0
 THEN RAISE EXCEPTION 'Owner-only Auth Admin guard must be installed first'; END IF;
 IF position('STAGING_CONFIRMED_OWNER_ACTIVE_PROFILE_V1' in original) > 0
 THEN RAISE EXCEPTION 'Owner profile status override already installed'; END IF;
 IF position($needle$   case when new.raw_app_meta_data->>'mela_staging_invited'='true'
     and new.raw_user_meta_data->>'test_account'='true'$needle$ in original) = 0
 THEN RAISE EXCEPTION 'Profile status logic changed; abort'; END IF;
 revised := replace(original,$needle$   case when new.raw_app_meta_data->>'mela_staging_invited'='true'
     and new.raw_user_meta_data->>'test_account'='true'$needle$,$replacement$   case
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
     and new.raw_user_meta_data->>'test_account'='true'$replacement$);
 EXECUTE revised;
 IF position('STAGING_CONFIRMED_OWNER_ACTIVE_PROFILE_V1' in pg_get_functiondef('private.handle_new_auth_user()'::regprocedure))=0
 THEN RAISE EXCEPTION 'Owner active-profile rule missing'; END IF;
END;
$apply$;
