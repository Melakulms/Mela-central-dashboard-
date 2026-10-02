begin;
do $test$
declare
  v_learner uuid:=gen_random_uuid();
  v_guardian uuid:=gen_random_uuid();
  v_outsider uuid:=gen_random_uuid();
  v_result jsonb;
  v_blocked boolean:=false;
begin
  insert into auth.users(id,email,raw_app_meta_data,raw_user_meta_data,email_confirmed_at,created_at,updated_at)
  values
    (v_learner,v_learner::text||'@example.invalid','{"provider":"email"}','{"full_name":"Guardian test learner","role":"student"}',now(),now(),now()),
    (v_guardian,v_guardian::text||'@example.invalid','{"provider":"email"}','{"full_name":"Guardian test parent","role":"parent"}',now(),now(),now()),
    (v_outsider,v_outsider::text||'@example.invalid','{"provider":"email"}','{"full_name":"Guardian test outsider","role":"parent"}',now(),now(),now());
  execute 'reset role';
  insert into public.guardian_relationships(learner_id,guardian_user_id,relationship,status,verified_at,verified_by)
  values(v_learner,v_guardian,'parent','verified',now(),v_guardian);

  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_guardian,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  v_result:=public.get_my_guardian_learner_progress(v_learner);
  if v_result->'learner'->>'full_name'<>'Guardian test learner' then raise exception 'guardian summary missing learner'; end if;

  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_outsider,'role','authenticated')::text,true);
  begin
    perform public.get_my_guardian_learner_progress(v_learner);
  exception when others then v_blocked:=true;
  end;
  if not v_blocked then raise exception 'unlinked outsider could read learner progress'; end if;
end $test$;
rollback;
select 'PASS: verified guardian progress access; unlinked outsider denied; fixtures rolled back' as result;
