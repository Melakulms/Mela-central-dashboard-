-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20261002044330
CREATE OR REPLACE FUNCTION private.is_admin_user()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  select
    (session_user in ('postgres','service_role')
      and coalesce(current_setting('role', true), 'none') in ('none','postgres','service_role')
      and (select auth.uid()) is null)
    or coalesce((select auth.role()) = 'service_role', false)
    or exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid()) and p.role = 'admin'::public.user_role
        and p.account_status = 'active' and p.deleted_at is null
    )
$function$;

CREATE OR REPLACE FUNCTION private.enforce_profile_role_change_authority()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
begin
  if new.role is distinct from old.role and not private.is_admin_user() then
    raise exception 'role changes are server/admin managed';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.guard_profile_sensitive_updates()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
begin
  if private.is_admin_user() then return new; end if;
  if (select auth.uid()) is null then raise exception 'authentication required'; end if;
  if new.role is distinct from old.role or new.account_status is distinct from old.account_status
    or new.email_verified is distinct from old.email_verified or new.phone_verified is distinct from old.phone_verified
    or new.coin_balance is distinct from old.coin_balance
    or new.verified_passport_badge_count is distinct from old.verified_passport_badge_count
    or new.deleted_at is distinct from old.deleted_at then
    raise exception 'sensitive profile fields are server-managed';
  end if;
  if new.id is distinct from old.id then raise exception 'profile id is immutable'; end if;
  return new;
end;
$function$;
;
