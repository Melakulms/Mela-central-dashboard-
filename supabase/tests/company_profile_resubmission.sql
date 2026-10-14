begin;
do $test$
declare uid uuid:=gen_random_uuid(); request_id uuid; count_requests integer;
begin
  insert into auth.users(id,email,raw_app_meta_data,raw_user_meta_data,email_confirmed_at,created_at,updated_at)
  values(uid,uid::text||'@example.invalid','{"provider":"email"}','{"full_name":"QA company","role":"company"}',now(),now(),now());
  update auth.users set email_confirmed_at=now() where id=uid;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',uid,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  perform public.complete_my_profile_v37('QA representative','en',null,null,'QA company','{"company_name":"QA original","industry":"Education"}'::jsonb);
  select id into request_id from public.employer_registration_requests where applicant_user_id=uid;
  perform public.complete_my_profile_v37('QA representative','en',null,null,'QA company','{"company_name":"QA corrected","industry":"Technology","website":"https://example.org","status":"approved"}'::jsonb);
  if not exists(select 1 from public.employer_registration_requests where id=request_id and company_name='QA corrected' and industry='Technology' and website='https://example.org' and status='pending') then
    raise exception 'Company correction was not persisted or approval boundary changed';
  end if;
  select count(*) into count_requests from public.employer_registration_requests where applicant_user_id=uid;
  if count_requests<>1 then raise exception 'Duplicate request created by profile correction'; end if;
end $test$;
rollback;
select 'PASS: company corrections persist without duplicating requests or granting approval' as result;
