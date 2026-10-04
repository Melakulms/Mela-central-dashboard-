begin;

do $test$
declare
  learner uuid:=gen_random_uuid();
  guardian uuid:=gen_random_uuid();
  outsider uuid:=gen_random_uuid();
  dashboard jsonb;
  practice jsonb;
  recs jsonb;
  arena jsonb;
  analytics jsonb;
  guardian_result jsonb;
  educator_blocked boolean:=false;
  outsider_blocked boolean:=false;
begin
  if exists (
    select 1
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.proname in (
        'activate_my_educator_profile','get_my_arena_creator_analytics','get_my_arena_stats',
        'get_my_dashboard_v36','get_my_guardian_learner_progress','get_my_practice_dashboard',
        'get_my_practice_recommendations'
      )
      and p.prosecdef
  ) then raise exception 'one or more owner-scoped public wrappers still use SECURITY DEFINER'; end if;

  if has_function_privilege('anon','public.activate_my_educator_profile(uuid,text,text[],text[])','EXECUTE')
     or has_function_privilege('anon','public.get_my_arena_creator_analytics(integer)','EXECUTE')
     or has_function_privilege('anon','public.get_my_arena_stats()','EXECUTE')
     or has_function_privilege('anon','public.get_my_dashboard_v36()','EXECUTE')
     or has_function_privilege('anon','public.get_my_guardian_learner_progress(uuid)','EXECUTE')
     or has_function_privilege('anon','public.get_my_practice_dashboard()','EXECUTE')
     or has_function_privilege('anon','public.get_my_practice_recommendations(integer)','EXECUTE')
     or has_function_privilege('anon','private.activate_my_educator_profile(uuid,text,text[],text[])','EXECUTE')
     or has_function_privilege('anon','private.get_my_arena_creator_analytics(integer)','EXECUTE')
     or has_function_privilege('anon','private.get_my_arena_stats()','EXECUTE')
     or has_function_privilege('anon','private.get_my_dashboard_v36()','EXECUTE')
     or has_function_privilege('anon','private.get_guardian_learner_progress(uuid)','EXECUTE')
     or has_function_privilege('anon','private.get_my_practice_dashboard()','EXECUTE')
     or has_function_privilege('anon','private.get_my_practice_recommendations(integer)','EXECUTE') then
    raise exception 'anonymous owner-scoped execution was exposed';
  end if;

  insert into auth.users(id,email,raw_app_meta_data,raw_user_meta_data,email_confirmed_at,created_at,updated_at)
  values
    (learner,learner::text||'@example.invalid','{"provider":"email"}','{"full_name":"Owner API learner","role":"student"}',now(),now(),now()),
    (guardian,guardian::text||'@example.invalid','{"provider":"email"}','{"full_name":"Owner API guardian","role":"parent"}',now(),now(),now()),
    (outsider,outsider::text||'@example.invalid','{"provider":"email"}','{"full_name":"Owner API outsider","role":"parent"}',now(),now(),now());

  update public.profiles
  set account_status='active',email_verified=true,role_selected_at=now()
  where id in (learner,guardian,outsider);

  insert into public.guardian_relationships(learner_id,guardian_user_id,relationship,status,verified_at,verified_by)
  values(learner,guardian,'parent','verified',now(),guardian);

  perform set_config('request.jwt.claims',jsonb_build_object('sub',learner,'role','authenticated','aal','aal1')::text,true);
  execute 'set local role authenticated';
  select public.get_my_dashboard_v36() into dashboard;
  select public.get_my_practice_dashboard() into practice;
  select public.get_my_practice_recommendations(5) into recs;
  select public.get_my_arena_stats() into arena;
  select public.get_my_arena_creator_analytics(30) into analytics;
  if dashboard is null or practice is null or recs is null or arena is null or analytics is null then
    raise exception 'owner-scoped learner read failed';
  end if;
  begin
    perform public.activate_my_educator_profile(gen_random_uuid(),'Educator',array['Mathematics'],array['secondary']);
  exception when others then
    if position('teacher account required' in sqlerrm)>0 then educator_blocked:=true; else raise; end if;
  end;
  if not educator_blocked then raise exception 'student activated educator profile'; end if;
  execute 'reset role';

  perform set_config('request.jwt.claims',jsonb_build_object('sub',guardian,'role','authenticated','aal','aal1')::text,true);
  execute 'set local role authenticated';
  select public.get_my_guardian_learner_progress(learner) into guardian_result;
  if guardian_result->'learner'->>'id' is null then raise exception 'verified guardian progress read failed'; end if;
  execute 'reset role';

  perform set_config('request.jwt.claims',jsonb_build_object('sub',outsider,'role','authenticated','aal','aal1')::text,true);
  execute 'set local role authenticated';
  begin
    perform public.get_my_guardian_learner_progress(learner);
  exception when others then
    if position('verified guardian relationship required' in sqlerrm)>0 then outsider_blocked:=true; else raise; end if;
  end;
  if not outsider_blocked then raise exception 'unlinked outsider read learner progress'; end if;
end
$test$;

rollback;
