begin;

do $test$
declare
  outsider uuid:=gen_random_uuid();
  admin_id uuid;
  blocked boolean:=false;
  row_count bigint;
begin
  if (select p.prosecdef from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='get_proctor_review_queue' and pg_get_function_identity_arguments(p.oid)='p_limit integer') then
    raise exception 'proctor queue public wrapper must be SECURITY INVOKER';
  end if;
  if not (select p.prosecdef from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='get_proctor_review_queue' and pg_get_function_identity_arguments(p.oid)='p_limit integer') then
    raise exception 'private proctor queue implementation must remain privileged';
  end if;
  if has_function_privilege('anon','public.get_proctor_review_queue(integer)','EXECUTE')
     or has_function_privilege('anon','private.get_proctor_review_queue(integer)','EXECUTE') then
    raise exception 'anonymous proctor review access was exposed';
  end if;

  insert into auth.users(id,email,raw_app_meta_data,raw_user_meta_data,email_confirmed_at,created_at,updated_at)
  values(outsider,outsider::text||'@example.invalid','{"provider":"email"}','{"full_name":"Proctor outsider","role":"student"}',now(),now(),now());
  perform set_config('request.jwt.claims',jsonb_build_object('sub',outsider,'role','authenticated','aal','aal1')::text,true);
  execute 'set local role authenticated';
  begin
    perform count(*) from public.get_proctor_review_queue(5);
  exception when others then
    if position('admin authorization with MFA required' in sqlerrm)>0 then blocked:=true; else raise; end if;
  end;
  if not blocked then raise exception 'non-admin accessed proctor review queue'; end if;
  execute 'reset role';

  select au.user_id into admin_id
  from admin.admin_users au join public.profiles p on p.id=au.user_id
  where au.active=true and p.account_status='active' and p.deleted_at is null
  order by au.created_at limit 1;
  if admin_id is null then raise exception 'no active admin fixture available'; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_id,'role','authenticated','aal','aal2')::text,true);
  execute 'set local role authenticated';
  select count(*) into row_count from public.get_proctor_review_queue(5);
  if row_count<0 then raise exception 'unreachable'; end if;
end
$test$;

rollback;
