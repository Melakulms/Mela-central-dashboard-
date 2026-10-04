-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812220106
create or replace function private.protect_profile_security_fields()
returns trigger
language plpgsql
set search_path='pg_catalog','public','private'
as $$
declare
  v_uid uuid := (select auth.uid());
  v_is_admin boolean := false;
  v_server boolean := current_user in ('postgres','service_role');
begin
  if v_server then
    new.updated_at:=now();
    return new;
  end if;

  if v_uid is not null then
    select exists(select 1 from public.profiles p where p.id=v_uid and p.role='admin'::public.user_role) into v_is_admin;

    if new.role is distinct from old.role and (v_uid=old.id or not v_is_admin) then
      raise exception 'role can only be changed by an administrator';
    end if;
    if new.coin_balance is distinct from old.coin_balance and (v_uid=old.id or not v_is_admin) then
      raise exception 'coin balance can only be changed by an administrator or trusted backend';
    end if;
    if new.verified_passport_badge_count is distinct from old.verified_passport_badge_count and (v_uid=old.id or not v_is_admin) then
      raise exception 'verified passport badge count is system managed';
    end if;
  end if;
  new.updated_at:=now();
  return new;
end;$$;
revoke all on function private.protect_profile_security_fields() from public,anon,authenticated;

;
