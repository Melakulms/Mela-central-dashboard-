-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260822044546
create or replace function private.protect_application_identity_fields() returns trigger language plpgsql set search_path to '' as $function$
declare v_uid uuid := (select auth.uid()); v_admin boolean := false; v_server boolean := current_user in ('service_role','postgres');
begin
  if v_uid is not null then select exists(select 1 from public.profiles p where p.id=v_uid and p.role='admin'::public.user_role) into v_admin; end if;
  if not v_admin and not v_server then
    if new.applicant_id is distinct from old.applicant_id or new.user_id is distinct from old.user_id or new.opportunity_id is distinct from old.opportunity_id then
      raise exception 'application identity fields are immutable';
    end if;
    if new.passport_snapshot is distinct from old.passport_snapshot then
      raise exception 'passport snapshot is server managed';
    end if;
    if new.reviewer_id is distinct from old.reviewer_id or new.reviewed_at is distinct from old.reviewed_at then
      raise exception 'review fields are server managed';
    end if;
  end if;
  return new;
end;
$function$;
drop trigger if exists trg_protect_application_identity_fields on public.applications;
create trigger trg_protect_application_identity_fields before update on public.applications for each row execute function private.protect_application_identity_fields();
;
