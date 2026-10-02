begin;
do $test$
declare teacher uuid:=gen_random_uuid(); learner uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid(); org uuid; classroom uuid; stage text; result jsonb; created public.educator_classrooms; denied boolean:=false;
begin
 insert into auth.users(id,email,raw_app_meta_data,raw_user_meta_data,email_confirmed_at,created_at,updated_at)
 select u,u::text||'@example.invalid','{"provider":"email"}','{"full_name":"Classroom rollback test","role":"student"}',now(),now(),now() from unnest(array[teacher,learner,outsider]) u;
 update public.profiles set role='teacher',account_status='active',email_verified=true where id=teacher;
 select stage_key into stage from public.education_audience_stages order by stage_key limit 1;
 insert into public.sector_partner_organizations(partner_type_key,organization_name) select partner_type_key,'Rollback classroom partner' from public.sector_partner_types order by partner_type_key limit 1 returning id into org;
 insert into public.educator_profiles(user_id,partner_organization_id) values(teacher,org);
 update public.profiles set education_stage_key=stage where id=learner;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',teacher,'role','authenticated')::text,true);
 execute 'set local role authenticated';
 created:=public.create_my_classroom('Rollback classroom',stage,'Mathematics');
 classroom:=created.id;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',learner,'role','authenticated')::text,true);
 perform public.join_educator_classroom(created.join_code);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',outsider,'role','authenticated')::text,true);
 execute 'set local role authenticated';
 begin perform public.get_my_classroom_detail(classroom);exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'outsider could read classroom data';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',teacher,'role','authenticated')::text,true);
 result:=public.get_my_classroom_detail(classroom);
 if result->'classroom'->>'id'<>classroom::text or jsonb_array_length(result->'learners')<>1 then raise exception 'teacher access broken';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',learner,'role','authenticated')::text,true);
 result:=public.get_my_classroom_detail(classroom);
 if result->'classroom'->>'id'<>classroom::text then raise exception 'member access broken';end if;
end $test$;
rollback;
select 'PASS: outsider denied; teacher and current member access preserved; fixtures rolled back' as result;
