begin;
do $test$
declare
 owner_id uuid:=gen_random_uuid(); learner uuid:=gen_random_uuid(); stranger uuid:=gen_random_uuid(); company uuid; task uuid; member uuid; proposal uuid; awarded public.freelance_contracts; blocked boolean:=false; message text;
begin
 insert into auth.users(id,email,raw_app_meta_data,raw_user_meta_data,email_confirmed_at,created_at,updated_at)
 select u,u::text||'@example.invalid','{"provider":"email"}','{"full_name":"Marketplace rollback test","role":"student"}',now(),now(),now() from unnest(array[owner_id,learner,stranger]) u;
 update public.profiles set role='employer',account_status='active',email_verified=true where id=owner_id;
 insert into public.employers(company_name,owner_id,verified,verification_status) values('Rollback marketplace owner',owner_id,true,'verified') returning id into company;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
 execute 'set local role authenticated';
 insert into public.marketplace_tasks(employer_id,posted_by,title,status) values(company,owner_id,'Caller authority fixture','open') returning id into task;
 update public.marketplace_tasks set title='Allowed title change' where id=task;
 begin update public.marketplace_tasks set assigned_to=learner where id=task; exception when others then blocked:=true; end;
 if not blocked then raise exception 'direct client forged task assignment'; end if;
 blocked:=false;
 begin update public.marketplace_tasks set status='completed' where id=task; exception when others then blocked:=true; end;
 if not blocked then raise exception 'direct client forged completed task'; end if;
 execute 'reset role';
 insert into public.marketplace_submissions(task_id,user_id,status,proposal_text) values(task,learner,'pending','Rollback-only proposal') returning id into proposal;
 execute 'set local role authenticated';
 execute 'reset role';
 insert into public.employer_members(employer_id,user_id,member_role,status) values(company,learner,'recruiter','active');
 execute 'set local role authenticated';
 blocked:=false;
 begin
   update public.employer_members set user_id=stranger where employer_id=company and user_id=learner;
 exception when others then
   get stacked diagnostics message=message_text;
   blocked:=message in ('employer membership identity is admin managed','permission denied for table employer_members');
 end;
 if not blocked then raise exception 'membership identity write was not denied: %',coalesce(message,'no exception'); end if;
 awarded:=public.award_freelance_task(proposal,100,'Rollback fixture terms');
 if awarded.status<>'proposed' or awarded.freelancer_id<>learner then raise exception 'authorized award RPC failed'; end if;
end $test$;
rollback;
select 'PASS: allowed employer posting/editing; direct client assignment/completion/membership-identity forgery denied; authorized award preserved; fixtures rolled back' as regression_result;
