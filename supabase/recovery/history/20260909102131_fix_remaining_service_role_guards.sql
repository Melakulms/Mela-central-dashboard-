-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260909102131

-- Most guard triggers in this codebase already correctly handle service_role via
-- `current_user in ('service_role','postgres')` (process_employer_registration_request,
-- protect_opportunity_moderation_v35, protect_profile_security_fields, enforce_report_workflow
-- all do this correctly). Two things still needed:

-- 1) Belt-and-suspenders: add the same current_user check to is_admin_user() alongside
--    the auth.role() check already applied, matching the codebase's own established idiom
--    without discarding the already-verified fix.
CREATE OR REPLACE FUNCTION private.is_admin_user()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select current_user in ('service_role','postgres')
     or (select auth.role()) = 'service_role'
     or coalesce((select p.role='admin'::public.user_role from public.profiles p where p.id=(select auth.uid())), false)
$function$;

-- 2) guard_profile_sensitive_updates raises "authentication required" on a null auth.uid()
--    BEFORE ever reaching an is_admin_user() check -- this is the one guard on `profiles`
--    that does NOT follow the codebase's own service_role convention. Confirmed by
--    reproduction: this specifically blocked mela-admin-api's user.update action even
--    after the is_admin_user() fix, because the null-check fires first.
CREATE OR REPLACE FUNCTION private.guard_profile_sensitive_updates()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid := auth.uid();
begin
  if current_user in ('service_role','postgres') then return new; end if;
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
$function$;

-- 3) Minor polish: audit_report_change records a NULL actor for service_role calls
--    since it uses plain auth.uid() with no fallback. mela-admin-api's report.resolve
--    action already sets assigned_to to the real admin's user id before this trigger
--    fires -- fall back to that, same pattern audit_employer_registration_change
--    already uses correctly for reviewed_by.
CREATE OR REPLACE FUNCTION private.audit_report_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
begin
  if tg_op='UPDATE' and (new.status is distinct from old.status or new.assigned_to is distinct from old.assigned_to) then
    insert into public.admin_audit_logs(actor_id,action,entity_type,entity_id,details)
    values(coalesce((select auth.uid()),new.assigned_to),'report_'||new.status,'report',new.id,jsonb_build_object('old_status',old.status,'new_status',new.status,'assigned_to',new.assigned_to));
    if new.reporter_id is not null and new.status in ('resolved','dismissed') then perform private.create_notification(new.reporter_id,'Report update','Your report was '||new.status||'.','reports',new.id); end if;
  end if; return new;
end;$function$;

;
