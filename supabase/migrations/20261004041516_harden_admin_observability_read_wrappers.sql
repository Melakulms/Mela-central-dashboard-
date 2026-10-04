create or replace function public.get_platform_launch_readiness()
returns jsonb
language sql
security invoker
set search_path to ''
as $function$
  select private.get_platform_launch_readiness();
$function$;

create or replace function public.get_platform_operational_health()
returns jsonb
language sql
security invoker
set search_path to ''
as $function$
  select private.get_platform_operational_health();
$function$;

revoke all on function private.get_platform_launch_readiness() from public, anon;
revoke all on function private.get_platform_operational_health() from public, anon;
grant execute on function private.get_platform_launch_readiness() to authenticated, service_role;
grant execute on function private.get_platform_operational_health() to authenticated, service_role;

revoke all on function public.get_platform_launch_readiness() from public, anon;
revoke all on function public.get_platform_operational_health() from public, anon;
grant execute on function public.get_platform_launch_readiness() to authenticated, service_role;
grant execute on function public.get_platform_operational_health() to authenticated, service_role;
