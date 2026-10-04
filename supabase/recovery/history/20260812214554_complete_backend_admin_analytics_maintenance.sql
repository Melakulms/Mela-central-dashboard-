-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812214554
-- Admin/moderation hardening, audit automation, and scheduled maintenance.

revoke insert,update on public.reports from authenticated;
grant insert (reporter_id,target_type,target_id,reason,details) on public.reports to authenticated;
grant update (status,assigned_to,resolution_notes) on public.reports to authenticated;

create or replace function private.enforce_report_workflow()
returns trigger language plpgsql set search_path='pg_catalog','public','private' as $$
declare v_admin boolean:=private.is_admin_user();
begin
  if tg_op='INSERT' then new.status:='open'; new.assigned_to:=null; new.resolution_notes:=null; new.resolved_at:=null; return new; end if;
  if new.id is distinct from old.id or new.reporter_id is distinct from old.reporter_id or new.target_type is distinct from old.target_type or new.target_id is distinct from old.target_id or new.reason is distinct from old.reason or new.details is distinct from old.details or new.created_at is distinct from old.created_at then raise exception 'report submission fields are immutable'; end if;
  if not v_admin and current_user not in ('service_role','postgres') then raise exception 'admin access required'; end if;
  if new.status is distinct from old.status and not ((old.status='open' and new.status in ('reviewing','resolved','dismissed')) or (old.status='reviewing' and new.status in ('open','resolved','dismissed'))) then raise exception 'invalid report status transition'; end if;
  if new.status in ('resolved','dismissed') then new.resolved_at=coalesce(old.resolved_at,now()); else new.resolved_at=null; end if;
  return new;
end;$$;
drop trigger if exists trg_enforce_report_workflow on public.reports;
create trigger trg_enforce_report_workflow before insert or update on public.reports for each row execute function private.enforce_report_workflow();

create or replace function private.audit_report_change()
returns trigger language plpgsql security definer set search_path='pg_catalog','public','private' as $$
begin
  if tg_op='UPDATE' and (new.status is distinct from old.status or new.assigned_to is distinct from old.assigned_to) then
    insert into public.admin_audit_logs(actor_id,action,entity_type,entity_id,details)
    values((select auth.uid()),'report_'||new.status,'report',new.id,jsonb_build_object('old_status',old.status,'new_status',new.status,'assigned_to',new.assigned_to));
    if new.reporter_id is not null and new.status in ('resolved','dismissed') then perform private.create_notification(new.reporter_id,'Report update','Your report was '||new.status||'.','reports',new.id); end if;
  end if; return new;
end;$$;
revoke all on function private.audit_report_change() from public,anon,authenticated;
drop trigger if exists trg_audit_report_change on public.reports;
create trigger trg_audit_report_change after update on public.reports for each row execute function private.audit_report_change();

create or replace function private.audit_employer_registration_change()
returns trigger language plpgsql security definer set search_path='pg_catalog','public','private' as $$
begin
  if new.status is distinct from old.status and new.status in ('approved','rejected') then
    insert into public.admin_audit_logs(actor_id,action,entity_type,entity_id,details)
    values((select auth.uid()),'employer_registration_'||new.status,'employer_registration_request',new.id,jsonb_build_object('company_name',new.company_name,'employer_id',new.employer_id));
    perform private.create_notification(new.applicant_user_id,'Employer registration '||new.status,case when new.status='approved' then 'Your organization registration was approved.' else coalesce(new.review_notes,'Your organization registration was not approved.') end,'employer_registration_requests',new.id);
  end if; return new;
end;$$;
revoke all on function private.audit_employer_registration_change() from public,anon,authenticated;
drop trigger if exists trg_audit_employer_registration_change on public.employer_registration_requests;
create trigger trg_audit_employer_registration_change after update of status on public.employer_registration_requests for each row execute function private.audit_employer_registration_change();

create or replace function private.audit_employer_verification_change()
returns trigger language plpgsql security definer set search_path='pg_catalog','public','private' as $$
begin
  if new.verified is distinct from old.verified or new.verification_status is distinct from old.verification_status then
    insert into public.admin_audit_logs(actor_id,action,entity_type,entity_id,details)
    values((select auth.uid()),'employer_verification_changed','employer',new.id,jsonb_build_object('verified',new.verified,'verification_status',new.verification_status));
    perform private.create_notification(new.owner_id,'Employer verification update','Organization verification status: '||new.verification_status||'.','employers',new.id);
  end if; return new;
end;$$;
revoke all on function private.audit_employer_verification_change() from public,anon,authenticated;
drop trigger if exists trg_audit_employer_verification_change on public.employers;
create trigger trg_audit_employer_verification_change after update of verified,verification_status on public.employers for each row execute function private.audit_employer_verification_change();

create or replace function private.record_business_event()
returns trigger language plpgsql security definer set search_path='pg_catalog','public' as $$
declare v_user uuid; v_name text; v_props jsonb;
begin
  if tg_table_name='applications' then v_user:=new.applicant_id; v_name:='application_'||new.status; v_props:=jsonb_build_object('application_id',new.id,'opportunity_id',new.opportunity_id);
  elsif tg_table_name='verified_skills' then v_user:=new.user_id; v_name:='verified_skill_issued'; v_props:=jsonb_build_object('skill_name',new.skill_name,'category',new.category);
  elsif tg_table_name='user_badges' then v_user:=new.user_id; v_name:='badge_earned'; v_props:=jsonb_build_object('badge_id',new.badge_id);
  elsif tg_table_name='freelance_contracts' then v_user:=new.freelancer_id; v_name:='freelance_contract_'||new.status; v_props:=jsonb_build_object('contract_id',new.id,'task_id',new.task_id);
  elsif tg_table_name='mentorship_sessions' then v_user:=new.mentee_id; v_name:='mentorship_session_'||new.status; v_props:=jsonb_build_object('session_id',new.id,'mentor_id',new.mentor_id);
  else return new; end if;
  insert into public.platform_events(user_id,event_name,properties) values(v_user,v_name,v_props); return new;
end;$$;
revoke all on function private.record_business_event() from public,anon,authenticated;

drop trigger if exists trg_event_application_insert on public.applications;
create trigger trg_event_application_insert after insert on public.applications for each row execute function private.record_business_event();
drop trigger if exists trg_event_application_status on public.applications;
create trigger trg_event_application_status after update of status on public.applications for each row when (new.status is distinct from old.status) execute function private.record_business_event();
drop trigger if exists trg_event_verified_skill on public.verified_skills;
create trigger trg_event_verified_skill after insert on public.verified_skills for each row execute function private.record_business_event();
drop trigger if exists trg_event_badge on public.user_badges;
create trigger trg_event_badge after insert on public.user_badges for each row execute function private.record_business_event();
drop trigger if exists trg_event_contract_insert on public.freelance_contracts;
create trigger trg_event_contract_insert after insert on public.freelance_contracts for each row execute function private.record_business_event();
drop trigger if exists trg_event_contract_status on public.freelance_contracts;
create trigger trg_event_contract_status after update of status on public.freelance_contracts for each row when (new.status is distinct from old.status) execute function private.record_business_event();
drop trigger if exists trg_event_mentorship_insert on public.mentorship_sessions;
create trigger trg_event_mentorship_insert after insert on public.mentorship_sessions for each row execute function private.record_business_event();
drop trigger if exists trg_event_mentorship_status on public.mentorship_sessions;
create trigger trg_event_mentorship_status after update of status on public.mentorship_sessions for each row when (new.status is distinct from old.status) execute function private.record_business_event();
revoke update,delete on public.platform_events from authenticated,anon;

alter table public.marketplace_tasks drop constraint if exists marketplace_task_status_chk;
alter table public.marketplace_tasks add constraint marketplace_task_status_chk check (status in ('draft','open','assigned','in_progress','completed','cancelled','disputed','expired'));

create or replace function private.run_mela_maintenance()
returns jsonb language plpgsql security definer set search_path='pg_catalog','public','private' as $$
declare v_opps int:=0; v_tasks int:=0; v_pay int:=0; v_esc int:=0;
begin
  update public.opportunities set status='closed',verified_active=false,updated_at=now() where status='open' and deadline<current_date; get diagnostics v_opps=row_count;
  perform set_config('mela.system_workflow','on',true);
  update public.marketplace_tasks set status='expired',updated_at=now() where status='open' and assigned_to is null and deadline is not null and deadline<now(); get diagnostics v_tasks=row_count;
  update public.marketplace_submissions s set status='rejected',reviewed_at=now(),updated_at=now() where s.status='pending' and exists(select 1 from public.marketplace_tasks t where t.id=s.task_id and t.status='expired');
  update public.payments set status='expired',updated_at=now(),failure_reason=coalesce(failure_reason,'Checkout expired before verification') where status in ('initiated','pending') and created_at<now()-interval '24 hours'; get diagnostics v_pay=row_count;
  update public.escrow_payment_attempts set status='expired',updated_at=now(),failure_reason=coalesce(failure_reason,'Checkout expired before verification') where status in ('initiated','pending') and created_at<now()-interval '24 hours'; get diagnostics v_esc=row_count;
  return jsonb_build_object('closed_opportunities',v_opps,'expired_tasks',v_tasks,'expired_course_payments',v_pay,'expired_escrow_payments',v_esc,'ran_at',now());
end;$$;
revoke all on function private.run_mela_maintenance() from public,anon,authenticated;

create extension if not exists pg_cron;
do $$
begin
  if exists(select 1 from cron.job where jobname='mela-hourly-maintenance') then perform cron.unschedule('mela-hourly-maintenance'); end if;
  perform cron.schedule('mela-hourly-maintenance','7 * * * *',$cron$select private.run_mela_maintenance();$cron$);
end $$;

create index if not exists reports_status_created_idx on public.reports(status,created_at);
create index if not exists admin_audit_logs_created_idx on public.admin_audit_logs(created_at desc);
create index if not exists platform_events_event_created_idx on public.platform_events(event_name,created_at desc);

;
