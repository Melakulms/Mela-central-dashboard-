-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260822044512
create or replace function private.protect_employer_verification_fields() returns trigger language plpgsql set search_path to 'pg_catalog','public','private' as $function$
declare v_uid uuid := (select auth.uid()); v_admin boolean := false; v_server boolean := current_user in ('service_role','postgres');
begin
  if v_uid is not null then
    select exists(select 1 from public.profiles p where p.id=v_uid and p.role='admin'::public.user_role) into v_admin;
  end if;
  if not v_admin and not v_server and v_uid is not null and new.owner_id is distinct from old.owner_id then
    raise exception 'employer owner is admin managed';
  end if;
  if not v_admin and not v_server and v_uid is not null and (
    new.verified is distinct from old.verified or new.verification_status is distinct from old.verification_status or new.verified_at is distinct from old.verified_at or new.verified_by is distinct from old.verified_by or new.verification_notes is distinct from old.verification_notes
  ) then raise exception 'employer verification fields are admin managed'; end if;
  if (v_admin or v_server) and (new.verified is distinct from old.verified or new.verification_status is distinct from old.verification_status) then
    new.verified_by:=coalesce(v_uid,new.verified_by); new.verified_at:=now();
  end if;
  new.updated_at:=now(); return new;
end;$function$;
;
