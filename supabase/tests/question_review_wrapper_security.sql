begin;

do $test$
declare
  fixture_user uuid := gen_random_uuid();
  slice_id bigint;
  blocked boolean := false;
  queue_result jsonb;
begin
  if (select p.prosecdef from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='get_question_review_queue_v18' and pg_get_function_identity_arguments(p.oid)='p_program_key text, p_limit integer') then
    raise exception 'question review queue public wrapper must be SECURITY INVOKER';
  end if;
  if (select p.prosecdef from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='get_question_review_slice_v18' and pg_get_function_identity_arguments(p.oid)='p_slice_id bigint') then
    raise exception 'question review slice public wrapper must be SECURITY INVOKER';
  end if;

  if has_function_privilege('anon','public.get_question_review_queue_v18(text,integer)','EXECUTE')
     or has_function_privilege('anon','public.get_question_review_slice_v18(bigint)','EXECUTE')
     or has_function_privilege('anon','private.get_question_review_queue_v18(text,integer)','EXECUTE')
     or has_function_privilege('anon','private.get_question_review_slice_v18(bigint)','EXECUTE') then
    raise exception 'anonymous reviewer execution was exposed';
  end if;

  if not has_function_privilege('authenticated','public.get_question_review_queue_v18(text,integer)','EXECUTE')
     or not has_function_privilege('authenticated','public.get_question_review_slice_v18(bigint)','EXECUTE')
     or not has_function_privilege('authenticated','private.get_question_review_queue_v18(text,integer)','EXECUTE')
     or not has_function_privilege('authenticated','private.get_question_review_slice_v18(bigint)','EXECUTE') then
    raise exception 'authenticated reviewer execution path is incomplete';
  end if;

  if has_table_privilege('authenticated','private.mela_question_review_slices_v18','SELECT')
     or has_table_privilege('authenticated','private.mela_question_review_decisions_v18','SELECT')
     or has_table_privilege('anon','private.mela_question_review_slices_v18','SELECT')
     or has_table_privilege('anon','private.mela_question_review_decisions_v18','SELECT') then
    raise exception 'private question review tables are directly readable';
  end if;

  insert into auth.users(id,email,raw_app_meta_data,raw_user_meta_data,email_confirmed_at,created_at,updated_at)
  values(fixture_user,fixture_user::text||'@example.invalid','{"provider":"email"}','{"full_name":"Review security fixture","role":"student"}',now(),now(),now());

  select min(id) into slice_id from private.mela_question_review_slices_v18;
  if slice_id is null then raise exception 'question review slice fixture is missing'; end if;

  perform set_config('request.jwt.claims',jsonb_build_object('sub',fixture_user,'role','authenticated')::text,true);
  execute 'set local role authenticated';

  select public.get_question_review_queue_v18(null,5) into queue_result;
  if queue_result <> '[]'::jsonb then raise exception 'unqualified learner received a question review queue'; end if;

  begin
    perform public.get_question_review_slice_v18(slice_id);
  exception when others then
    if position('verified educator subject access required' in sqlerrm)>0 then blocked:=true; else raise; end if;
  end;
  if not blocked then raise exception 'unqualified learner opened a review slice'; end if;
end
$test$;

rollback;
