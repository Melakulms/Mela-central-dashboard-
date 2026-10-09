
begin;

do $fixture$
declare ready uuid; emptycourse uuid; paid uuid; hidden uuid; u uuid;
begin
 select id into u from public.profiles where role='student' and account_status='active' and deleted_at is null limit 1;
 if u is null then raise exception 'Active learner required'; end if;
 insert into public.courses(title,slug,price_cents,is_published,credential_type) values('QA ready','qa-ready-'||gen_random_uuid(),0,true,'Course Completion') returning id into ready;
 insert into public.courses(title,slug,price_cents,is_published) values('QA empty','qa-empty-'||gen_random_uuid(),0,true) returning id into emptycourse;
 insert into public.courses(title,slug,price_cents,is_published) values('QA paid','qa-paid-'||gen_random_uuid(),100,true) returning id into paid;
 insert into public.courses(title,slug,price_cents,is_published) values('QA hidden','qa-hidden-'||gen_random_uuid(),0,false) returning id into hidden;
 insert into public.course_lessons(course_id,module_title,module_position,title,lesson_position,duration_minutes,content_text,is_preview)
 values(ready,'Introduction',1,'First',1,10,'Complete lesson one.',true),(ready,'Introduction',1,'Second',2,10,'Complete lesson two.',false),
 (paid,'Introduction',1,'Paid',1,10,'Paid lesson.',false),(hidden,'Introduction',1,'Unpublished',1,10,'Unpublished lesson.',false);
 perform set_config('test.course_ready',ready::text,true);
 perform set_config('test.course_empty',emptycourse::text,true);
 perform set_config('test.course_paid',paid::text,true);
 perform set_config('test.course_hidden',hidden::text,true);
 perform set_config('test.learner',u::text,true);
 perform set_config('test.inventory_oid','admin.course_content_inventory'::regclass::oid::text,true);
end $fixture$;
set local role anon;
do $anon$
begin
 if has_function_privilege('anon','public.get_mela_academy_catalog()','execute') then raise exception 'Anonymous catalog permission'; end if;
 if has_function_privilege('anon','public.enroll_mela_course(uuid)','execute') then raise exception 'Anonymous enrollment permission'; end if;
 if has_table_privilege('anon',current_setting('test.inventory_oid')::oid,'select') then raise exception 'Private inventory exposed'; end if;
end $anon$;
reset role;
select set_config('request.jwt.claim.sub',current_setting('test.learner'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('test.learner'),'role','authenticated')::text,true);
set local role authenticated;
do $learner$
declare cat jsonb; ready uuid:=current_setting('test.course_ready')::uuid; u uuid:=auth.uid(); l1 uuid; l2 uuid; n int;
begin
 cat:=public.get_mela_academy_catalog();
 if exists(select 1 from jsonb_array_elements(cat) c where c->>'id'=current_setting('test.course_hidden')) then raise exception 'Unpublished course leaked'; end if;
 if not exists(select 1 from jsonb_array_elements(cat) c where c->>'id'=current_setting('test.course_ready') and (c->>'lesson_count')::int=2 and (c->>'preview_lesson_count')::int=1 and (c->>'content_available')::boolean) then raise exception 'Wrong lesson metadata'; end if;

 perform public.enroll_mela_course(ready); perform public.enroll_mela_course(ready);
 select count(*) into n from public.course_enrollments where user_id=u and course_id=ready;
 if n<>1 then raise exception 'Duplicate enrollment'; end if;
 select id into l1 from public.course_lessons where course_id=ready and lesson_position=1;
 select id into l2 from public.course_lessons where course_id=ready and lesson_position=2;
 if l1 is null or l2 is null then raise exception 'Enrolled lesson access failed'; end if;
 insert into public.lesson_progress(user_id,lesson_id) values(u,l1) on conflict(user_id,lesson_id) do nothing;
 if (select progress_pct from public.course_enrollments where user_id=u and course_id=ready)<>50 then raise exception 'Progress not saved'; end if;
 perform public.enroll_mela_course(ready);
 if (select progress_pct from public.course_enrollments where user_id=u and course_id=ready)<>50 then raise exception 'Enrollment retry reset progress'; end if;
 insert into public.lesson_progress(user_id,lesson_id) values(u,l2) on conflict(user_id,lesson_id) do nothing;
 insert into public.lesson_progress(user_id,lesson_id) values(u,l2) on conflict(user_id,lesson_id) do nothing;
 if not exists(select 1 from public.course_enrollments where user_id=u and course_id=ready and progress_pct=100 and completed_at is not null) then raise exception 'Completion failed'; end if;
 if (select count(*) from public.course_certificates where user_id=u and course_id=ready)<>1 then raise exception 'Certificate duplicated or missing'; end if;
 begin perform public.enroll_mela_course(current_setting('test.course_empty')::uuid); raise exception 'EMPTY_ALLOWED'; exception when others then if sqlerrm='EMPTY_ALLOWED' or sqlerrm not like '%prepared%' then raise; end if; end;
 begin insert into public.course_enrollments(user_id,course_id,progress_pct) values(u,current_setting('test.course_empty')::uuid,0); raise exception 'EMPTY_DIRECT_ALLOWED'; exception when others then if sqlerrm='EMPTY_DIRECT_ALLOWED' or sqlerrm not like '%prepared%' then raise; end if; end;
 begin perform public.enroll_mela_course(current_setting('test.course_paid')::uuid); raise exception 'PAID_ALLOWED'; exception when others then if sqlerrm='PAID_ALLOWED' or sqlerrm not like '%deferred%' then raise; end if; end;
 begin perform public.enroll_mela_course(current_setting('test.course_hidden')::uuid); raise exception 'HIDDEN_ALLOWED'; exception when others then if sqlerrm='HIDDEN_ALLOWED' or sqlerrm not like '%available%' then raise; end if; end;
 if has_table_privilege('authenticated',current_setting('test.inventory_oid')::oid,'select') then raise exception 'Admin course inventory exposed'; end if;
end $learner$;
reset role;
rollback;
select true as course_catalog_access_enrollment_completion_retries_passed;
