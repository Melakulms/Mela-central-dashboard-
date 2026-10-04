begin;

do $test$
declare
  fixture_user uuid:=gen_random_uuid();
  admin_id uuid;
  blocked_ready boolean:=false;
  blocked_health boolean:=false;
  readiness jsonb;
  health jsonb;
begin
  if (select p.prosecdef from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='get_platform_launch_readiness' and pg_get_function_identity_arguments(p.oid)='') then
    raise exception 'launch readiness public wrapper must be SECURITY INVOKER';
  end if;
  if (select p.prosecdef from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='get_platform_operational_health' and pg_get_function_identity_arguments(p.oid)='') then
    raise exception 'operational health public wrapper must be SECURITY INVOKER';
  end if;
  if has_function_privilege('anon','public.get_platform_launch_readiness()','EXECUTE')
     or has_function_privilege('anon','public.get_platform_operational_health()','EXECUTE')
     or has_function_privilege('anon','private.get_platform_launch_readiness()','EXECUTE')
     or has_function_privilege('anon','private.get_platform_operational_health()','EXECUTE') then
    raise exception 'anonymous admin observability execution was exposed';
  end if;
  if not has_function_privilege('authenticated','public.get_platform_launch_readiness()','EXECUTE')
     or not has_function_privilege('authenticated','public.get_platform_operational_health()','EXECUTE')
     or not has_function_privilege('authenticated','private.get_platform_launch_readiness()','EXECUTE')
     or not has_function_privilege('authenticated','private.get_platform_operational_health()','EXECUTE') then
    raise exception 'authenticated admin observability execution path is incomplete';
  end if;

  insert into auth.users(id,email,raw_app_meta_data,raw_user_meta_data,email_confirmed_at,created_at,updated_at)
  values(fixture_user,fixture_user::text||'@example.invalid','{"provider":"email"}','{"full_name":"Observability outsider","role":"student"}',now(),now(),now());
  perform set_config('request.jwt.claims',jsonb_build_object('sub',fixture_user,'role','authenticated','aal','aal1')::text,true);
  execute 'set local role authenticated';
  begin perform public.get_platform_launch_readiness(); exception when others then if position('admin authorization required' in sqlerrm)>0 then blocked_ready:=true; else raise; end if; end;
  begin perform public.get_platform_operational_health(); exception when others then if position('admin authorization required' in sqlerrm)>0 then blocked_health:=true; else raise; end if; end;
  if not blocked_ready or not blocked_health then raise exception 'non-admin accessed admin observability'; end if;
  execute 'reset role';

  select au.user_id into admin_id from admin.admin_users au join public.profiles p on p.id=au.user_id where au.active=true and p.account_status='active' and p.deleted_at is null order by au.created_at limit 1;
  if admin_id is null then raise exception 'no active admin fixture available'; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_id,'role','authenticated','aal','aal2')::text,true);
  execute 'set local role authenticated';
  select public.get_platform_launch_readiness() into readiness;
  select public.get_platform_operational_health() into health;
  if readiness->>'decision' is null then raise exception 'MFA admin launch readiness failed'; end if;
  if health is null then raise exception 'MFA admin operational health failed'; end if;
end
$test$;

rollback;
