-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260816232332
create or replace function public.get_frontend_build_for_service(p_version text)
returns jsonb
language sql
stable
security definer
set search_path=''
as $$
  select coalesce((select jsonb_build_object('version',b.version,'html',b.html,'sha256',b.sha256) from private.mela_frontend_builds b where b.version=p_version),'{}'::jsonb);
$$;
revoke all on function public.get_frontend_build_for_service(text) from public, anon, authenticated;
grant execute on function public.get_frontend_build_for_service(text) to service_role;
;
