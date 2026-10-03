-- Rollback-only regression for the production assessment submission boundary.
begin;
do $test$
declare
  v_user uuid := gen_random_uuid();
  v_outsider uuid := gen_random_uuid();
  v_admin uuid := gen_random_uuid();
  v_skill uuid;
  v_assessment uuid := gen_random_uuid();
  v_question uuid := gen_random_uuid();
  v_attempt uuid;
  v_overtime uuid;
  v_status text;
  v_score numeric;
  v_passed boolean;
  v_verified integer;
  v_blocked boolean := false;
begin
  select id into v_skill from public.skills order by id limit 1;
  if v_skill is null then raise exception 'No skill fixture available'; end if;

  insert into auth.users(id,email,raw_app_meta_data,raw_user_meta_data,email_confirmed_at,created_at,updated_at)
  values
    (v_user, v_user::text||'@example.invalid', '{"provider":"email"}', '{"full_name":"Assessment learner","role":"student"}', now(), now(), now()),
    (v_outsider, v_outsider::text||'@example.invalid', '{"provider":"email"}', '{"full_name":"Assessment outsider","role":"student"}', now(), now(), now()),
    (v_admin, v_admin::text||'@example.invalid', '{"provider":"email"}', '{"full_name":"Assessment admin","role":"admin"}', now(), now(), now());

  update public.profiles
     set role='student',education_stage_key='university',preferred_language='English',account_status='active',deleted_at=null
   where id in (v_user,v_outsider);
  update public.profiles
     set role='admin',education_stage_key='university',preferred_language='English',account_status='active',deleted_at=null
   where id=v_admin;

  insert into public.skill_assessments(
    id,skill_id,category,title,description,duration_minutes,pass_score,max_attempts,is_proctored,status,
    question_count,shuffle_questions,shuffle_choices,cooldown_hours
  ) values(
    v_assessment,v_skill,'Technology'::public.launch_category,'Rollback assessment integrity test',
    'Temporary rollback-only assessment',30,70,3,false,'published',1,false,false,0
  );

  insert into public.assessment_language_certifications(
    assessment_id,language_code,status,certified_at,certification_metadata
  ) values(v_assessment,'en','certified',now(),'{"test":true}'::jsonb);

  insert into public.assessment_questions(
    id,assessment_id,question_order,prompt,question_type,choices,points,active,language_code,difficulty
  ) values(v_question,v_assessment,1,'Choose A','single_choice','["A","B"]'::jsonb,1,true,'en',1);
  insert into private.assessment_answer_keys(question_id,correct_answer,explanation)
  values(v_question,to_jsonb('A'::text),'Rollback-only answer key');

  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_user,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  insert into public.assessment_attempts(assessment_id,user_id)
  values(v_assessment,v_user) returning id into v_attempt;

  begin
    perform public.submit_my_assessment_attempt(v_attempt);
  exception when others then
    v_blocked := position('Answer every question' in sqlerrm)>0;
  end;
  if not v_blocked then raise exception 'Incomplete assessment submission was not blocked'; end if;

  insert into public.assessment_responses(attempt_id,question_id,response)
  values(v_attempt,v_question,to_jsonb('A'::text));
  perform public.submit_my_assessment_attempt(v_attempt);

  select status,score,passed into v_status,v_score,v_passed
  from public.assessment_attempts where id=v_attempt;
  if v_status<>'graded' or v_score<>100 or v_passed is distinct from true then
    raise exception 'Expected graded 100%% pass, got status %, score %, passed %',v_status,v_score,v_passed;
  end if;

  select count(*) into v_verified
  from public.verified_skills
  where user_id=v_user and verification_source='Mela assessment: Rollback assessment integrity test';
  if v_verified<>1 then raise exception 'Expected one verified skill, got %',v_verified; end if;

  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_outsider,'role','authenticated')::text,true);
  v_blocked:=false;
  begin
    perform public.submit_my_assessment_attempt(v_attempt);
  exception when others then v_blocked:=true;
  end;
  if not v_blocked then raise exception 'Outsider could submit another user assessment'; end if;

  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_user,'role','authenticated')::text,true);
  insert into public.assessment_attempts(assessment_id,user_id)
  values(v_assessment,v_user) returning id into v_overtime;
  insert into public.assessment_responses(attempt_id,question_id,response)
  values(v_overtime,v_question,to_jsonb('A'::text));

  execute 'reset role';
  -- Fixture time travel uses the database maintenance context, not a profile role.
  -- An admin profile alone no longer grants administrator authority.
  perform set_config('request.jwt.claims','{}',true);
  update public.assessment_attempts set started_at=now()-interval '31 minutes' where id=v_overtime;

  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_user,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  perform public.submit_my_assessment_attempt(v_overtime);
  select status,score,passed into v_status,v_score,v_passed
  from public.assessment_attempts where id=v_overtime;
  if v_status<>'void' or v_score is not null or v_passed is distinct from false then
    raise exception 'Overtime attempt was not voided safely: status %, score %, passed %',v_status,v_score,v_passed;
  end if;
end $test$;
rollback;
select 'PASS: assessment submission integrity; fixtures rolled back' as result;
