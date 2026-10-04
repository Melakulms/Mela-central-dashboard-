-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260814170055
create table if not exists public.platform_operational_alerts (
  alert_key text primary key,
  severity text not null check(severity in ('info','warning','critical')),
  category text not null,
  title text not null,
  details jsonb not null default '{}'::jsonb,
  status text not null default 'open' check(status in ('open','resolved')),
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  resolved_at timestamptz,
  updated_at timestamptz not null default now()
);

create table if not exists public.platform_health_snapshots (
  id bigint generated always as identity primary key,
  checked_at timestamptz not null default now(),
  overall_status text not null check(overall_status in ('healthy','degraded','critical')),
  checks jsonb not null,
  open_warning_count integer not null default 0,
  open_critical_count integer not null default 0
);

create index if not exists platform_operational_alerts_status_severity_idx on public.platform_operational_alerts(status,severity,last_seen_at desc);
create index if not exists platform_health_snapshots_checked_idx on public.platform_health_snapshots(checked_at desc);

alter table public.platform_operational_alerts enable row level security;
alter table public.platform_health_snapshots enable row level security;
revoke all on public.platform_operational_alerts,public.platform_health_snapshots from anon,authenticated;
grant select on public.platform_operational_alerts,public.platform_health_snapshots to authenticated;
create policy platform_operational_alerts_admin_read on public.platform_operational_alerts for select to authenticated using(private.is_admin_user());
create policy platform_health_snapshots_admin_read on public.platform_health_snapshots for select to authenticated using(private.is_admin_user());

create or replace function private.set_operational_alert(p_key text,p_condition boolean,p_severity text,p_category text,p_title text,p_details jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path='' as $$ begin
  if p_condition then
    insert into public.platform_operational_alerts(alert_key,severity,category,title,details,status,first_seen_at,last_seen_at,resolved_at,updated_at)
    values(p_key,p_severity,p_category,p_title,coalesce(p_details,'{}'::jsonb),'open',now(),now(),null,now())
    on conflict(alert_key) do update set severity=excluded.severity,category=excluded.category,title=excluded.title,details=excluded.details,status='open',last_seen_at=now(),resolved_at=null,updated_at=now();
  else
    update public.platform_operational_alerts set status='resolved',resolved_at=coalesce(resolved_at,now()),updated_at=now() where alert_key=p_key and status='open';
  end if;
end $$;

create or replace function private.collect_platform_operational_health()
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_public_tables int; v_rls_tables int; v_public_definers int; v_failed_cron int; v_stale_sources int; v_overdue_rights int; v_warn int; v_crit int; v_status text; v_checks jsonb;
begin
  select count(*)::int,count(*) filter(where c.relrowsecurity)::int into v_public_tables,v_rls_tables from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r';
  select count(*)::int into v_public_definers from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef and (has_function_privilege('anon',p.oid,'EXECUTE') or has_function_privilege('authenticated',p.oid,'EXECUTE'));
  select count(*)::int into v_failed_cron from cron.job_run_details d join cron.job j on j.jobid=d.jobid where d.start_time>=now()-interval '24 hours' and d.status<>'succeeded' and j.active=true;
  select count(*)::int into v_stale_sources from public.opportunities where employer_id is null and source_type in ('official_external','platform_curated') and status='open' and (source_verified_at is null or source_verified_at<now()-interval '30 days' or deadline<current_date);
  select count(*)::int into v_overdue_rights from public.data_subject_requests where status in ('pending','in_review') and requested_at<now()-interval '14 days';

  perform private.set_operational_alert('security.rls_coverage',v_public_tables<>v_rls_tables,'critical','security','One or more public tables do not have RLS',jsonb_build_object('public_tables',v_public_tables,'rls_enabled',v_rls_tables));
  perform private.set_operational_alert('security.public_security_definer',v_public_definers>0,'critical','security','Public SECURITY DEFINER execution exposure detected',jsonb_build_object('count',v_public_definers));
  perform private.set_operational_alert('automation.cron_failures_24h',v_failed_cron>0,'warning','automation','Scheduled jobs failed in the last 24 hours',jsonb_build_object('failed_runs',v_failed_cron));
  perform private.set_operational_alert('content.stale_external_sources',v_stale_sources>0,'warning','content','Official external opportunity sources need re-verification or closure',jsonb_build_object('count',v_stale_sources));
  perform private.set_operational_alert('privacy.overdue_requests',v_overdue_rights>0,'critical','privacy','Data-rights requests are older than the internal 14-day escalation threshold',jsonb_build_object('count',v_overdue_rights));
  perform private.set_operational_alert('finance.payments_enabled_without_launch_evidence',public.platform_feature_enabled('payments') and exists(select 1 from public.platform_launch_requirements where requirement_key='payments_provider' and manual_status<>'complete'),'critical','finance','Payments enabled before provider launch evidence is complete','{}'::jsonb);
  perform private.set_operational_alert('finance.payouts_enabled_without_launch_evidence',public.platform_feature_enabled('payouts') and exists(select 1 from public.platform_launch_requirements where requirement_key='payout_provider' and manual_status<>'complete'),'critical','finance','Payouts enabled before KYC/provider launch evidence is complete','{}'::jsonb);
  perform private.set_operational_alert('realtime.video_enabled_without_launch_evidence',public.platform_feature_enabled('video_calls') and exists(select 1 from public.platform_launch_requirements where requirement_key='video_provider' and manual_status<>'complete'),'critical','realtime','Video Calls enabled before media-provider/device evidence is complete','{}'::jsonb);

  select count(*) filter(where status='open' and severity='warning')::int,count(*) filter(where status='open' and severity='critical')::int into v_warn,v_crit from public.platform_operational_alerts;
  v_status:=case when v_crit>0 then 'critical' when v_warn>0 then 'degraded' else 'healthy' end;
  v_checks:=jsonb_build_object('public_tables',v_public_tables,'rls_enabled',v_rls_tables,'public_security_definer_exposure',v_public_definers,'cron_failures_24h',v_failed_cron,'stale_external_sources',v_stale_sources,'overdue_data_rights_requests',v_overdue_rights,'payments_enabled',public.platform_feature_enabled('payments'),'payouts_enabled',public.platform_feature_enabled('payouts'),'video_calls_enabled',public.platform_feature_enabled('video_calls'));
  insert into public.platform_health_snapshots(overall_status,checks,open_warning_count,open_critical_count) values(v_status,v_checks,v_warn,v_crit);
  delete from public.platform_health_snapshots where checked_at<now()-interval '90 days';
  return jsonb_build_object('status',v_status,'checks',v_checks,'warnings',v_warn,'critical',v_crit,'checked_at',now());
end $$;

create or replace function private.get_platform_operational_health()
returns jsonb language plpgsql security definer set search_path='' as $$ declare v_uid uuid:=(select auth.uid()); v jsonb; begin
 if v_uid is null or not private.is_admin_user() then raise exception 'admin authorization required'; end if;
 select jsonb_build_object('latest',(select to_jsonb(s) from public.platform_health_snapshots s order by checked_at desc limit 1),'open_alerts',coalesce((select jsonb_agg(to_jsonb(a) order by case a.severity when 'critical' then 1 when 'warning' then 2 else 3 end,a.last_seen_at desc) from public.platform_operational_alerts a where a.status='open'),'[]'::jsonb),'recent_snapshots',coalesce((select jsonb_agg(to_jsonb(x) order by x.checked_at desc) from (select * from public.platform_health_snapshots order by checked_at desc limit 48) x),'[]'::jsonb)) into v; return v; end $$;
create or replace function public.get_platform_operational_health() returns jsonb language sql set search_path='' as $$ select private.get_platform_operational_health(); $$;
revoke execute on function private.set_operational_alert(text,boolean,text,text,text,jsonb) from public,anon,authenticated;
revoke execute on function private.collect_platform_operational_health() from public,anon,authenticated;
revoke execute on function private.get_platform_operational_health() from public,anon;
grant execute on function private.set_operational_alert(text,boolean,text,text,text,jsonb),private.collect_platform_operational_health(),private.get_platform_operational_health() to service_role;
grant execute on function private.get_platform_operational_health() to authenticated;
revoke execute on function public.get_platform_operational_health() from public,anon;
grant execute on function public.get_platform_operational_health() to authenticated;

do $$ declare v_jobid bigint; begin
 select jobid into v_jobid from cron.job where jobname='mela-operational-health';
 if v_jobid is not null then perform cron.unschedule(v_jobid); end if;
 perform cron.schedule('mela-operational-health','*/15 * * * *','select private.collect_platform_operational_health();');
end $$;

update public.platform_launch_requirements set evidence_note='Internal database/security/cron/content/privacy/provider-feature health monitoring now runs every 15 minutes and retains 90 days of snapshots. Hosted frontend and Edge-runtime error alerting must still be verified in Preview/Staging before this requirement is marked complete.',updated_at=now() where requirement_key='observability';

select private.collect_platform_operational_health();
;
