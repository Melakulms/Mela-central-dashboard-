begin;
do $test$
declare
  v_user uuid:=gen_random_uuid();
  v_course uuid;
  v_lesson1 uuid;
  v_lesson2 uuid;
  v_code text;
  v_progress integer;
  v_completed timestamptz;
  v_count integer;
  v_blocked boolean:=false;
begin
  insert into auth.users(id,email,raw_app_meta_data,raw_user_meta_data,email_confirmed_at,created_at,updated_at)
  values(v_user,v_user::text||'@example.invalid','{"provider":"email"}','{"full_name":"Course certificate test","role":"student"}',now(),now(),now());
  execute 'reset role';
  insert into public.courses(title,is_published,price_cents,credential_type)
  values('Rollback credential course',true,0,'Micro-Credential') returning id into v_course;
  insert into public.course_lessons(course_id,module_title,title,content_text,module_position,lesson_position)
  values(v_course,'Module','Lesson one','Body',1,1) returning id into v_lesson1;
  insert into public.course_lessons(course_id,module_title,title,content_text,module_position,lesson_position)
  values(v_course,'Module','Lesson two','Body',1,2) returning id into v_lesson2;

  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_user,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  insert into public.course_enrollments(user_id,course_id) values(v_user,v_course);
  insert into public.lesson_progress(user_id,lesson_id) values(v_user,v_lesson1);
  select progress_pct,completed_at into v_progress,v_completed from public.course_enrollments where user_id=v_user and course_id=v_course;
  if v_progress<>50 or v_completed is not null then raise exception 'partial course aggregation failed'; end if;
  select count(*) into v_count from public.course_certificates where user_id=v_user and course_id=v_course;
  if v_count<>0 then raise exception 'certificate issued before completion'; end if;

  insert into public.lesson_progress(user_id,lesson_id) values(v_user,v_lesson2);
  select progress_pct,completed_at into v_progress,v_completed from public.course_enrollments where user_id=v_user and course_id=v_course;
  if v_progress<>100 or v_completed is null then raise exception 'course completion aggregation failed'; end if;
  select certificate_code into v_code from public.course_certificates where user_id=v_user and course_id=v_course;
  if v_code is null then raise exception 'course certificate not issued'; end if;

  begin
    delete from public.lesson_progress where user_id=v_user and lesson_id=v_lesson1;
  exception when insufficient_privilege then v_blocked:=true;
  end;
  if not v_blocked then raise exception 'learner could delete completion evidence'; end if;

  select count(*) into v_count from public.verify_course_certificate(v_code)
  where valid=true and learner_name='Course certificate test' and course_title='Rollback credential course';
  if v_count<>1 then raise exception 'certificate verification failed'; end if;
end $test$;
rollback;
select 'PASS: lesson aggregation, credential issuance, evidence immutability, certificate verification; fixtures rolled back' as result;
