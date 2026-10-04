-- Phase 7: current admin authority for moderation and defense-in-depth for minor messaging.

drop policy if exists "Admins update reports" on public.reports;
create policy "Admins update reports"
on public.reports
for update
to authenticated
using (private.is_admin_user())
with check (private.is_admin_user());

drop policy if exists "Reports readable by reporter or admin" on public.reports;
create policy "Reports readable by reporter or admin"
on public.reports
for select
to authenticated
using (reporter_id = (select auth.uid()) or private.is_admin_user());

create or replace function private.enforce_report_safety_fields()
returns trigger
language plpgsql
set search_path to ''
as $function$
begin
  if nullif(btrim(coalesce(new.reason,'')), '') is null or char_length(btrim(new.reason)) > 160 then
    raise exception 'report reason is required and must be 160 characters or fewer';
  end if;
  if new.details is not null and char_length(new.details) > 4000 then
    raise exception 'report details must be 4000 characters or fewer';
  end if;

  if tg_op = 'INSERT' then
    if current_user not in ('postgres','service_role') and not private.is_admin_user() then
      if new.reporter_id is distinct from (select auth.uid()) then raise exception 'reporter must match signed-in user'; end if;
      new.status := 'open';
      new.assigned_to := null;
      new.resolution_notes := null;
      new.resolved_at := null;
    end if;
    new.reason := btrim(new.reason);
    new.details := nullif(btrim(coalesce(new.details,'')), '');
    return new;
  end if;

  if current_user not in ('postgres','service_role') and not private.is_admin_user() then
    raise exception 'only an MFA-authenticated administrator can moderate reports';
  end if;

  if new.reporter_id is distinct from old.reporter_id
     or new.target_type is distinct from old.target_type
     or new.target_id is distinct from old.target_id
     or new.reason is distinct from old.reason
     or new.details is distinct from old.details
     or new.created_at is distinct from old.created_at then
    raise exception 'report evidence fields are immutable after submission';
  end if;

  if new.status not in ('open','in_review','resolved','dismissed') then
    raise exception 'invalid report status';
  end if;

  if new.status in ('resolved','dismissed') then
    new.resolved_at := coalesce(new.resolved_at, now());
  elsif new.status in ('open','in_review') then
    new.resolved_at := null;
  end if;

  if new.resolution_notes is not null and char_length(new.resolution_notes) > 4000 then
    raise exception 'resolution notes must be 4000 characters or fewer';
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_enforce_report_safety_fields on public.reports;
create trigger trg_enforce_report_safety_fields
before insert or update on public.reports
for each row execute function private.enforce_report_safety_fields();

create or replace function private.enforce_minor_task_message_safeguarding()
returns trigger
language plpgsql
set search_path to ''
as $function$
declare
  v_stage text;
  v_status text;
begin
  select p.education_stage_key, p.learner_safety_status
    into v_stage, v_status
  from public.profiles p
  where p.id = new.sender_id;

  if v_stage like 'school_%' then
    raise exception 'private work messaging is not available to school-age learners';
  end if;

  if new.body is null or nullif(btrim(new.body), '') is null then
    raise exception 'message body is required';
  end if;
  if char_length(new.body) > 4000 then
    raise exception 'message body must be 4000 characters or fewer';
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_enforce_minor_task_message_safeguarding on public.task_messages;
create trigger trg_enforce_minor_task_message_safeguarding
before insert on public.task_messages
for each row execute function private.enforce_minor_task_message_safeguarding();
