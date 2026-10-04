begin;

do $test$
declare
  fixture_user uuid:=gen_random_uuid();
  admin_id uuid;
  program_key text;
  catalog jsonb;
  detail jsonb;
  overview jsonb;
  quality jsonb;
  compliance jsonb;
  quality_blocked boolean:=false;
  compliance_blocked boolean:=false;
begin
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.proname in ('get_data_protection_compliance_pack','get_my_question_bank_overview','get_question_catalog_v18','get_question_quality_progress_v21','get_question_subject_detail_v18')
      and p.prosecdef
  ) then raise exception 'one or more read-only public wrappers still use SECURITY DEFINER'; end if;

  if has_function_privilege('anon','public.get_data_protection_compliance_pack()','EXECUTE')
     or has_function_privilege('anon','public.get_my_question_bank_overview()','EXECUTE')
     or has_function_privilege('anon','public.get_question_catalog_v18(smallint)','EXECUTE')
     or has_function_privilege('anon','public.get_question_quality_progress_v21()','EXECUTE')
     or has_function_privilege('anon','public.get_question_subject_detail_v18(text)','EXECUTE')
     or has_function_privilege('anon','private.get_data_protection_compliance_pack()','EXECUTE')
     or has_function_privilege('anon','private.get_my_question_bank_overview()','EXECUTE')
     or has_function_privilege('anon','private.get_question_catalog_v18(smallint)','EXECUTE')
     or has_function_privilege('anon','private.get_question_quality_progress_v21()','EXECUTE')
     or has_function_privilege('anon','private.get_question_subject_detail_v18(text)','EXECUTE') then
    raise exception 'anonymous read-only API execution was exposed';
  end if;

  if not has_function_privilege('authenticated','public.get_data_protection_compliance_pack()','EXECUTE')
     or not has_function_privilege('authenticated','public.get_my_question_bank_overview()','EXECUTE')
     or not has_function_privilege('authenticated','public.get_question_catalog_v18(smallint)','EXECUTE')
     or not has_function_privilege('authenticated','public.get_question_quality_progress_v21()','EXECUTE')
     or not has_function_privilege('authenticated','public.get_question_subject_detail_v18(text)','EXECUTE') then
    raise exception 'authenticated read-only wrapper execution path is incomplete';
  end if;

  insert into auth.users(id,email,raw_app_meta_data,raw_user_meta_data,email_confirmed_at,created_at,updated_at)
  values(fixture_user,fixture_user::text||'@example.invalid','{"provider":"email"}','{"full_name":"Read API fixture","role":"student"}',now(),now(),now());

  select p.program_key into program_key
  from public.mela_learning_programs p
  where p.active and p.program_kind='school_subject' and p.grade_level between 1 and 12
  order by p.grade_level,p.display_order limit 1;
  if program_key is null then raise exception 'school program fixture missing'; end if;

  perform set_config('request.jwt.claims',jsonb_build_object('sub',fixture_user,'role','authenticated','aal','aal1')::text,true);
  execute 'set local role authenticated';

  select public.get_question_catalog_v18(null) into catalog;
  select public.get_question_subject_detail_v18(program_key) into detail;
  select public.get_my_question_bank_overview() into overview;
  if catalog is null or detail is null or overview is null then raise exception 'learner-safe read-only API failed'; end if;

  begin perform public.get_question_quality_progress_v21();
  exception when others then
    if position('verified educator or admin access required' in sqlerrm)>0 then quality_blocked:=true; else raise; end if;
  end;
  begin perform public.get_data_protection_compliance_pack();
  exception when others then
    if position('admin authorization required' in sqlerrm)>0 then compliance_blocked:=true; else raise; end if;
  end;
  if not quality_blocked or not compliance_blocked then raise exception 'learner accessed restricted read-only API'; end if;
  execute 'reset role';

  select au.user_id into admin_id
  from admin.admin_users au join public.profiles p on p.id=au.user_id
  where au.active=true and p.account_status='active' and p.deleted_at is null
  order by au.created_at limit 1;
  if admin_id is null then raise exception 'no active admin fixture available'; end if;

  perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_id,'role','authenticated','aal','aal2')::text,true);
  execute 'set local role authenticated';
  select public.get_question_quality_progress_v21() into quality;
  select public.get_data_protection_compliance_pack() into compliance;
  if quality is null or compliance is null then raise exception 'MFA admin restricted read-only API failed'; end if;
end
$test$;

rollback;
