-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260821233624
create or replace function private.guard_profile_sensitive_updates() returns trigger language plpgsql security definer set search_path = '' as $fn$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if not private.is_admin_user() and (
    new.role is distinct from old.role or
    new.account_status is distinct from old.account_status or
    new.email_verified is distinct from old.email_verified or
    new.phone_verified is distinct from old.phone_verified or
    new.coin_balance is distinct from old.coin_balance or
    new.verified_passport_badge_count is distinct from old.verified_passport_badge_count or
    new.deleted_at is distinct from old.deleted_at
  ) then
    raise exception 'sensitive profile fields are server-managed';
  end if;
  if not private.is_admin_user() and new.id is distinct from old.id then
    raise exception 'profile id is immutable';
  end if;
  return new;
end;
$fn$;
drop trigger if exists trg_guard_profile_sensitive_updates on public.profiles;
create trigger trg_guard_profile_sensitive_updates before update on public.profiles for each row execute function private.guard_profile_sensitive_updates();
revoke update on public.profiles from anon;

;
