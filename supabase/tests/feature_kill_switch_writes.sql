-- Rollback-only regression: disabled Earn & Work and Challenges must reject new user writes.
begin;
do $test$
declare
  v_user uuid := gen_random_uuid();
  v_admin uuid := gen_random_uuid();
  v_employer uuid := gen_random_uuid();
  v_task uuid := gen_random_uuid();
  v_challenge uuid := gen_random_uuid();
  v_error text;
begin
  insert into auth.users(id,email,raw_app_meta_data,raw_user_meta_data,email_confirmed_at,created_at,updated_at)
  values
    (v_user,v_user::text||'@example.invalid','{"provider":"email"}','{"full_name":"Kill switch learner","role":"student"}',now(),now(),now()),
    (v_admin,v_admin::text||'@example.invalid','{"provider":"email"}','{"full_name":"Kill switch admin","role":"admin"}',now(),now(),now());
  update public.profiles set role='student',education_stage_key='university',account_status='active',deleted_at=null where id=v_user;
  update public.profiles set role='admin',education_stage_key='university',account_status='active',deleted_at=null where id=v_admin;
  insert into public.employers(id,owner_id,company_name,verified,verification_status)
  values(v_employer,v_admin,'Rollback Employer',true,'verified');

  -- Admin preparation is allowed while the feature is held.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_admin,'role','authenticated')::text,true);
  insert into public.marketplace_tasks(id,employer_id,posted_by,title,status)
  values(v_task,v_employer,v_admin,'Rollback draft task','draft');
  insert into public.sponsored_challenges(id,sponsor_name,title,status,sponsor_employer_id,created_by)
  values(v_challenge,'Rollback Employer','Rollback draft challenge','draft',v_employer,v_admin);

  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_user,'role','authenticated')::text,true);

  v_error:=null;
  begin
    insert into public.marketplace_tasks(employer_id,posted_by,title,status)
    values(v_employer,v_user,'Blocked task','draft');
  exception when others then v_error:=sqlerrm; end;
  if coalesce(position('Earn & Work is temporarily disabled' in v_error),0)=0 then
    raise exception 'disabled Earn & Work did not block new task: %',v_error;
  end if;

  v_error:=null;
  begin
    insert into public.marketplace_submissions(task_id,user_id,status,proposal_text)
    values(v_task,v_user,'pending','Blocked proposal');
  exception when others then v_error:=sqlerrm; end;
  if coalesce(position('Earn & Work is temporarily disabled' in v_error),0)=0 then
    raise exception 'disabled Earn & Work did not block proposal: %',v_error;
  end if;

  v_error:=null;
  begin
    insert into public.challenge_participants(challenge_id,user_id,status)
    values(v_challenge,v_user,'active');
  exception when others then v_error:=sqlerrm; end;
  if coalesce(position('Sponsored challenges are temporarily disabled' in v_error),0)=0 then
    raise exception 'disabled Challenges did not block participation: %',v_error;
  end if;
end $test$;
rollback;
select 'PASS: disabled feature writes blocked; admin preparation allowed; fixtures rolled back' as result;
