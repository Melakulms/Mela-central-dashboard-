-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260813072552
create or replace function public.admin_command_center_system_status()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_jobs jsonb;
  v_db_size bigint;
  v_public_sd_auth integer;
begin
  select pg_database_size(current_database()) into v_db_size;
  select coalesce(jsonb_agg(jsonb_build_object(
    'jobid',j.jobid,
    'name',j.jobname,
    'schedule',j.schedule,
    'active',j.active,
    'last_status',r.status,
    'last_start',r.start_time,
    'last_end',r.end_time
  ) order by j.jobname),'[]'::jsonb)
  into v_jobs
  from cron.job j
  left join lateral (
    select status,start_time,end_time
    from cron.job_run_details d
    where d.jobid=j.jobid
    order by d.start_time desc
    limit 1
  ) r on true
  where j.jobname like 'mela-%';

  select count(*) into v_public_sd_auth
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.prosecdef=true and has_function_privilege('authenticated',p.oid,'EXECUTE');

  return jsonb_build_object(
    'database_size_bytes',v_db_size,
    'cron_jobs',v_jobs,
    'public_security_definer_auth_executable',v_public_sd_auth,
    'generated_at',now()
  );
end;
$$;

revoke all on function public.admin_command_center_system_status() from public, anon, authenticated;
grant execute on function public.admin_command_center_system_status() to service_role;

;
