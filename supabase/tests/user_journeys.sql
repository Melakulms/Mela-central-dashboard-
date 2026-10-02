begin;
do $test$
declare
  learner uuid := gen_random_uuid();
  parent_id uuid := gen_random_uuid();
  teacher_id uuid := gen_random_uuid();
  company_id uuid := gen_random_uuid();
  topic_id uuid;
  practice_id uuid;
  question_id uuid;
  link_code text;
  relationship_id uuid;
  blocked boolean := false;
begin
  insert into auth.users(id, email, raw_app_meta_data, raw_user_meta_data, email_confirmed_at, created_at, updated_at)
  values
    (learner, learner::text || '@example.invalid', '{"provider":"email"}', '{"full_name":"Transactional test learner","role":"student"}', now(), now(), now()),
    (parent_id, parent_id::text || '@example.invalid', '{"provider":"email"}', '{"full_name":"Transactional test parent","role":"parent"}', now(), now(), now()),
    (teacher_id, teacher_id::text || '@example.invalid', '{"provider":"email"}', '{"full_name":"Transactional test teacher","role":"teacher"}', now(), now(), now()),
    (company_id, company_id::text || '@example.invalid', '{"provider":"email"}', '{"full_name":"Transactional test company","role":"company"}', now(), now(), now());
  update auth.users set email_confirmed_at=now() where id in (learner,parent_id,teacher_id,company_id);
  execute 'reset role';
  update public.profiles set account_status='active' where id in (learner,parent_id);
  select t.id into topic_id from public.practice_topics t where t.is_published and exists (select 1 from public.practice_questions q where q.topic_id=t.id and q.is_published) limit 1;
  perform set_config('request.jwt.claims', jsonb_build_object('sub',learner,'role','authenticated')::text, true);
  execute 'set local role authenticated';
  if private.is_admin_user() then raise exception 'ordinary learner was treated as admin'; end if;
  update public.profiles set preferred_language='English' where id=learner;
  begin
    update public.profiles set role='admin' where id=learner;
  exception when others then blocked := true;
  end;
  if not blocked then raise exception 'self-promotion was permitted'; end if;
  link_code := public.create_parent_link_invite_v35();
  if link_code is null then raise exception 'student invitation was not generated'; end if;
  if topic_id is not null then
    practice_id := public.start_practice_session(topic_id, 'untimed', 1, null::smallint);
    select sq.question_id into question_id from public.practice_session_questions sq where sq.session_id=practice_id limit 1;
    perform public.submit_practice_response(practice_id,question_id,'{"answer":"regression check"}'::jsonb,1,null);
    perform public.complete_practice_session(practice_id);
  end if;
  perform set_config('request.jwt.claims', jsonb_build_object('sub',parent_id,'role','authenticated')::text, true);
  perform public.complete_my_profile_v37('Transactional test parent','en',null,null,null,'{}'::jsonb);
  relationship_id := public.redeem_parent_link_invite_v35(link_code);
  if relationship_id is null then raise exception 'parent link was not redeemed'; end if;
  if not exists (select 1 from public.guardian_relationships where id=relationship_id and guardian_user_id=parent_id and learner_id=learner and status='verified') then
    raise exception 'parent relationship was not persisted';
  end if;
  perform set_config('request.jwt.claims', jsonb_build_object('sub',teacher_id,'role','authenticated')::text, true);
  perform public.complete_my_profile_v37('Transactional test teacher','en',null,null,'Test school','{}'::jsonb);
  perform set_config('request.jwt.claims', jsonb_build_object('sub',company_id,'role','authenticated')::text, true);
  perform public.complete_my_profile_v37('Transactional test company','en',null,null,'Test company','{"company_name":"Transactional test company"}'::jsonb);
end $test$;
select 'PASS: database registration and confirmation for four roles; parent/teacher/company profile completion; self-promotion protection; practice; parent linking' as regression_result;
rollback;
