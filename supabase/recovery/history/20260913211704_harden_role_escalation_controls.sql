-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260913211704
create or replace function private.enforce_profile_role_change_authority()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.role is distinct from old.role then
    if current_user in ('service_role','postgres') then
      return new;
    end if;
    if private.is_admin_user() then
      return new;
    end if;
    raise exception 'role changes are server/admin managed';
  end if;
  return new;
end;
$$;

revoke all on function private.enforce_profile_role_change_authority() from public, anon, authenticated;

drop trigger if exists trg_enforce_profile_role_change_authority on public.profiles;
create trigger trg_enforce_profile_role_change_authority
before update of role on public.profiles
for each row
execute function private.enforce_profile_role_change_authority();
;
