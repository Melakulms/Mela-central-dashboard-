-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260813082412
create or replace function public.admin_command_center_snapshot()
returns jsonb
language sql
set search_path='pg_catalog','public'
as $function$
  select public.admin_command_center_snapshot_v2();
$function$;
revoke all on function public.admin_command_center_snapshot() from public, anon, authenticated;
grant execute on function public.admin_command_center_snapshot() to service_role;
;
