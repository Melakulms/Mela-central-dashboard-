begin;
do $test$
declare
 actor uuid:=gen_random_uuid(); company uuid:=gen_random_uuid(); learner uuid:=gen_random_uuid(); role_id uuid; request_id uuid; employer_id uuid; vacancy uuid;
 snapshot jsonb; result jsonb; blocked boolean:=false;
begin
 insert into auth.users(id,email,raw_app_meta_data,raw_user_meta_data,email_confirmed_at,created_at,updated_at) values
 (actor,actor::text||'@example.invalid','{"provider":"email"}','{"full_name":"Review test admin","role":"student"}',now(),now(),now()),
 (company,company::text||'@example.invalid','{"provider":"email"}','{"full_name":"Review test company","role":"company"}',now(),now(),now()),
 (learner,learner::text||'@example.invalid','{"provider":"email"}','{"full_name":"Review test learner","role":"student"}',now(),now(),now());
 update public.profiles set account_status='active',email_verified=true where id in (actor,company,learner);
 update public.profiles set education_stage_key='university' where id in (learner,actor);
 select id into role_id from admin.roles where key='super_admin';
 insert into admin.admin_users(user_id,role_id,active,mfa_required) values(actor,role_id,true,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',company,'role','authenticated')::text,true);
 execute 'set local role authenticated';
 insert into public.employer_registration_requests(applicant_user_id,company_name,sector_category,status) values(company,'Review regression company','Technology','pending') returning id into request_id;
 begin
  update public.employer_registration_requests set review_notes='Forged note' where id=request_id;
 exception when others then blocked:=true;
 end;
 if not blocked then raise exception 'Applicant could forge review notes'; end if;
 execute 'reset role';
 perform set_config('request.jwt.claims','{"role":"service_role"}',true);
 execute 'set local role service_role';
 select to_jsonb(r) into snapshot from public.employer_registration_requests r where id=request_id;
 result:=admin.apply_audited_update(actor,'employer.review',request_id::text,snapshot,jsonb_build_object('status','under_review','review_notes','Checking documentation','reviewed_by',actor),actor::text);
 result:=admin.apply_audited_update(actor,'employer.review',request_id::text,result,jsonb_build_object('status','approved','review_notes','Registration documents accepted','reviewed_by',actor),actor::text);
 employer_id:=(result->>'employer_id')::uuid;
 if employer_id is null then raise exception 'Approval did not create employer'; end if;
 if (select role::text from public.profiles where id=company)<>'employer' then raise exception 'Approval did not set employer role'; end if;
 select to_jsonb(e) into snapshot from public.employers e where id=employer_id;
 result:=admin.apply_audited_update(actor,'employer.verify',employer_id::text,snapshot,jsonb_build_object('verified',true,'verification_status','verified','verification_notes','Company documents verified','verified_by',actor,'verified_at',now()),actor::text);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',company,'role','authenticated')::text,true);
 execute 'set local role authenticated';
 insert into public.opportunities(posted_by,employer_id,title,description,location,deadline,sector_category,opportunity_type,employment_type_label,stipend_or_reward,status,moderation_status)
 values(company,employer_id,'Regression vacancy','Build educational tools','Addis Ababa',current_date+30,'Technology','jobs','Full time','ETB 20000 monthly','pending_review','pending_review') returning id into vacancy;
 execute 'reset role';
 perform set_config('request.jwt.claims','{"role":"service_role"}',true);
 execute 'set local role service_role';
 select to_jsonb(o) into snapshot from public.opportunities o where id=vacancy;
 result:=admin.apply_audited_update(actor,'opportunity.review',vacancy::text,snapshot,jsonb_build_object('moderation_status','approved','moderation_notes','Vacancy reviewed','reviewed_by',actor),actor::text);
 if result->>'status'<>'open' or (result->>'verified_active')::boolean is not true then raise exception 'Approved verified vacancy was not published: %',result; end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',learner,'role','authenticated')::text,true);
 execute 'set local role authenticated';
 if not exists(select 1 from public.opportunities where id=vacancy) then raise exception 'Learner cannot see approved vacancy'; end if;
 insert into public.applications(user_id,applicant_id,opportunity_id,cover_note) values(learner,learner,vacancy,'Regression application');
 if not exists(select 1 from public.applications where opportunity_id=vacancy and applicant_id=learner) then raise exception 'Application missing'; end if;
 execute 'reset role';
 perform set_config('request.jwt.claims','{"role":"service_role"}',true);
 execute 'set local role service_role';
 select to_jsonb(e) into snapshot from public.employers e where id=employer_id;
 result:=admin.apply_audited_update(actor,'employer.verify',employer_id::text,snapshot,jsonb_build_object('verified',false,'verification_status','suspended','verification_notes','Verification revoked','verified_by',actor),actor::text);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',learner,'role','authenticated')::text,true);
 execute 'set local role authenticated';
 if exists(select 1 from public.opportunities where id=vacancy) then raise exception 'Suspended employer vacancy remains public'; end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
 blocked:=false;
 begin
   insert into public.applications(user_id,applicant_id,opportunity_id) values(actor,actor,vacancy);
 exception when insufficient_privilege then blocked:=true;
 end;
 if not blocked then raise exception 'Suspended employer still accepted an application'; end if;
 execute 'reset role';
end;
$test$;
rollback;
