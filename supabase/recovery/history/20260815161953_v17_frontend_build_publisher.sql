-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815161953
create or replace function public.publish_frontend_build_v17(p_version text,p_html text,p_sha256 text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
begin
  if p_version !~ '^v[0-9]+$' then raise exception 'invalid version'; end if;
  if length(coalesce(p_html,'')) < 1000 then raise exception 'invalid html'; end if;
  if p_sha256 !~ '^[0-9a-f]{64}$' then raise exception 'invalid sha256'; end if;
  update private.mela_frontend_builds set active=false where active;
  insert into private.mela_frontend_builds(version,html,sha256,active,activated_at)
  values(p_version,p_html,p_sha256,true,now())
  on conflict(version) do update set html=excluded.html,sha256=excluded.sha256,active=true,activated_at=excluded.activated_at;
  return jsonb_build_object('version',p_version,'sha256',p_sha256,'bytes',octet_length(p_html),'active',true);
end;
$$;
revoke all on function public.publish_frontend_build_v17(text,text,text) from public,anon,authenticated;
grant execute on function public.publish_frontend_build_v17(text,text,text) to service_role;
;
