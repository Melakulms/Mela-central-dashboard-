-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20261003044111
create or replace function private.collect_platform_operational_health()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_public_tables int;
  v_rls_tables int;
  v_unreviewed_anon_definers int;
  v_allowlisted_anon_definers int;
  v_failed_cron int;
  v_stale_sources int;
  v_overdue_rights int;
  v_warn int;
  v_crit int;
  v_status text;
  v_checks jsonb;
begin
  select count(*)::int,count(*) filter(where c.relrowsecurity)::int
    into v_public_tables,v_rls_tables
  from pg_catalog.pg_class c
  join pg_catalog.pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relkind='r';

  select
    count(*) filter(where not (
      p.proname='verify_course_certificate'
      and pg_catalog.pg_get_function_identity_arguments(p.oid)='p_certificate_code text'
    ))::int,
    count(*) filter(where (
      p.proname='verify_course_certificate'
      and pg_catalog.pg_get_function_identity_arguments(p.oid)='p_certificate_code text'
    ))::int
  into v_unreviewed_anon_definers,v_allowlisted_anon_definers
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.prosecdef
    and has_function_privilege('anon',p.oid,'EXECUTE');

  select count(*)::int into v_failed_cron
  from cron.job_run_details d
  join cron.job j on j.jobid=d.jobid
  where d.start_time>=now()-interval '24 hours'
    and d.status<>'succeeded'
    and j.active=true;

  select count(*)::int into v_stale_sources
  from public.opportunities
  where employer_id is null
    and source_type in ('official_external','platform_curated')
    and status='open'
    and (source_verified_at is null or source_verified_at<now()-interval '30 days' or deadline<current_date);

  select count(*)::int into v_overdue_rights
  from public.data_subject_requests
  where status in ('pending','in_review') and requested_at<now()-interval '14 days';

  perform private.set_operational_alert('security.rls_coverage',v_public_tables<>v_rls_tables,'critical','security','One or more public tables do not have RLS',jsonb_build_object('public_tables',v_public_tables,'rls_enabled',v_rls_tables));
  perform private.set_operational_alert('security.public_security_definer',v_unreviewed_anon_definers>0,'critical','security','Unreviewed anonymous SECURITY DEFINER execution exposure detected',jsonb_build_object('unreviewed_anonymous_exposure',v_unreviewed_anon_definers,'allowlisted_public_verifiers',v_allowlisted_anon_definers));
  perform private.set_operational_alert('automation.cron_failures_24h',v_failed_cron>0,'warning','automation','Scheduled jobs failed in the last 24 hours',jsonb_build_object('failed_runs',v_failed_cron));
  perform private.set_operational_alert('content.stale_external_sources',v_stale_sources>0,'warning','content','Official external opportunity sources need re-verification or closure',jsonb_build_object('count',v_stale_sources));
  perform private.set_operational_alert('privacy.overdue_requests',v_overdue_rights>0,'critical','privacy','Data-rights requests are older than the internal 14-day escalation threshold',jsonb_build_object('count',v_overdue_rights));
  perform private.set_operational_alert('finance.payments_enabled_without_launch_evidence',public.platform_feature_enabled('payments') and exists(select 1 from public.platform_launch_requirements where requirement_key='payments_provider' and manual_status<>'complete'),'critical','finance','Payments enabled before provider launch evidence is complete','{}'::jsonb);
  perform private.set_operational_alert('finance.payouts_enabled_without_launch_evidence',public.platform_feature_enabled('payouts') and exists(select 1 from public.platform_launch_requirements where requirement_key='payout_provider' and manual_status<>'complete'),'critical','finance','Payouts enabled before KYC/provider launch evidence is complete','{}'::jsonb);
  perform private.set_operational_alert('realtime.video_enabled_without_launch_evidence',public.platform_feature_enabled('video_calls') and exists(select 1 from public.platform_launch_requirements where requirement_key='video_provider' and manual_status<>'complete'),'critical','realtime','Video Calls enabled before media-provider/device evidence is complete','{}'::jsonb);

  select count(*) filter(where status='open' and severity='warning')::int,
         count(*) filter(where status='open' and severity='critical')::int
    into v_warn,v_crit
  from public.platform_operational_alerts;

  v_status:=case when v_crit>0 then 'critical' when v_warn>0 then 'degraded' else 'healthy' end;
  v_checks:=jsonb_build_object(
    'public_tables',v_public_tables,
    'rls_enabled',v_rls_tables,
    'public_security_definer_exposure',v_unreviewed_anon_definers,
    'allowlisted_public_verifiers',v_allowlisted_anon_definers,
    'cron_failures_24h',v_failed_cron,
    'stale_external_sources',v_stale_sources,
    'overdue_data_rights_requests',v_overdue_rights,
    'payments_enabled',public.platform_feature_enabled('payments'),
    'payouts_enabled',public.platform_feature_enabled('payouts'),
    'video_calls_enabled',public.platform_feature_enabled('video_calls')
  );

  insert into public.platform_health_snapshots(overall_status,checks,open_warning_count,open_critical_count)
  values(v_status,v_checks,v_warn,v_crit);
  delete from public.platform_health_snapshots where checked_at<now()-interval '90 days';
  return jsonb_build_object('status',v_status,'checks',v_checks,'warnings',v_warn,'critical',v_crit,'checked_at',now());
end
$function$;
;
