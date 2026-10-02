begin;
do $test$
declare
  v_mentee uuid := gen_random_uuid();
  v_mentor uuid := gen_random_uuid();
  v_outsider uuid := gen_random_uuid();
  v_request uuid;
  v_session uuid;
  v_blocked boolean := false;
  v_count integer;
begin
  insert into auth.users(id,email,raw_app_meta_data,raw_user_meta_data,email_confirmed_at,created_at,updated_at)
  values
    (v_mentee,v_mentee::text||'@example.invalid','{"provider":"email"}','{"full_name":"Lifecycle mentee","role":"student"}',now(),now(),now()),
    (v_mentor,v_mentor::text||'@example.invalid','{"provider":"email"}','{"full_name":"Lifecycle mentor","role":"mentor"}',now(),now(),now()),
    (v_outsider,v_outsider::text||'@example.invalid','{"provider":"email"}','{"full_name":"Lifecycle outsider","role":"student"}',now(),now(),now());

  execute 'reset role';
  insert into public.mentor_profiles(user_id,headline,verified,active) values(v_mentor,'Lifecycle mentor',true,true);
  insert into public.mentorship_requests(mentor_id,mentee_id,topic,status)
  values(v_mentor,v_mentee,'Lifecycle authorization check','pending') returning id into v_request;

  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_mentor,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  perform public.respond_mentorship_request(v_request,'accepted');
  select count(*) into v_count from public.mentorship_sessions where request_id=v_request;
  if v_count<>0 then raise exception 'acceptance without preferred time unexpectedly created a session'; end if;

  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_mentee,'role','authenticated')::text,true);
  begin
    perform public.schedule_mentorship_session(v_request,now()+interval '2 days',30,null);
  exception when others then v_blocked:=true;
  end;
  if not v_blocked then raise exception 'mentee was allowed to schedule mentor-only session'; end if;

  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_mentor,'role','authenticated')::text,true);
  select id into v_session from public.schedule_mentorship_session(v_request,now()+interval '2 days',30,null);
  if v_session is null then raise exception 'mentor scheduling did not return a session'; end if;

  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_outsider,'role','authenticated')::text,true);
  select count(*) into v_count from public.mentorship_sessions where id=v_session;
  if v_count<>0 then raise exception 'outsider could read mentorship session'; end if;
  v_blocked:=false;
  begin
    perform public.cancel_mentorship_session(v_session,'outsider cancellation attempt');
  exception when others then v_blocked:=true;
  end;
  if not v_blocked then raise exception 'outsider was allowed to cancel mentorship session'; end if;

  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_mentee,'role','authenticated')::text,true);
  select count(*) into v_count from public.mentorship_sessions where id=v_session;
  if v_count<>1 then raise exception 'mentee could not read own mentorship session'; end if;
  perform public.cancel_mentorship_session(v_session,'participant cancellation check');
end $test$;
rollback;
select 'PASS: mentorship acceptance/schedule/read/cancel authorization; fixtures rolled back' as result;
