-- Phase 7: guardian verification must use the current MFA-backed admin authority.
create or replace function public.guard_guardian_relationship_identity()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if tg_op='UPDATE' and not private.is_admin_user() then
    if new.learner_id is distinct from old.learner_id
       or new.guardian_user_id is distinct from old.guardian_user_id
       or new.guardian_email is distinct from old.guardian_email
       or new.guardian_phone is distinct from old.guardian_phone
       or new.consent_version is distinct from old.consent_version
       or new.verified_at is distinct from old.verified_at
       or new.verified_by is distinct from old.verified_by
       or new.requested_at is distinct from old.requested_at then
      raise exception 'guardian relationship identity and verification fields are immutable for non-admin users';
    end if;
  end if;
  return new;
end;
$function$;

revoke all on function public.guard_guardian_relationship_identity() from public, anon, authenticated;
grant execute on function public.guard_guardian_relationship_identity() to service_role;
