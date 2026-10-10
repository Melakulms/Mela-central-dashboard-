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
  v_completed_request uuid;
  v_completed_session uuid:=gen_random_uuid();
  v_error text;
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

  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_mentor,'role','authenticated')::text,true);
  perform public.schedule_mentorship_session(v_request,now()+interval '3 days',45,null);
  if not exists(select 1 from public.mentorship_sessions where id=v_session and status='scheduled' and cancelled_at is null and duration_min=45) then raise exception 'cancelled session was not restored'; end if;
  perform public.schedule_mentorship_session(v_request,now()+interval '3 days',45,null);
  if (select count(*) from public.mentorship_sessions where request_id=v_request)<>1 then raise exception 'retry duplicated the session'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims','{}',true);
  insert into public.mentorship_requests(mentor_id,mentee_id,topic,status)
    values(v_mentor,v_mentee,'Completed history check','pending') returning id into v_completed_request;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_mentor,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  perform public.respond_mentorship_request(v_completed_request,'accepted');
  execute 'reset role';
  insert into public.mentorship_sessions(id,request_id,mentor_id,mentee_id,scheduled_at,status,completed_at)
    values(v_completed_session,v_completed_request,v_mentor,v_mentee,now()-interval '1 hour','completed',now()-interval '30 minutes');
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_mentee,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  perform public.rate_mentorship_session(v_completed_session,5::smallint,'Useful session');
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_mentor,'role','authenticated')::text,true);
  v_error:=null;
  begin
    perform public.schedule_mentorship_session(v_completed_request,now()+interval '4 days',30,null);
  exception when others then v_error:=sqlerrm; end;
  if v_error is distinct from 'completed mentorship sessions cannot be rescheduled' then
    raise exception 'completed rescheduling boundary failed: %',v_error; end if;
  if not exists(select 1 from public.mentorship_sessions where id=v_completed_session and status='completed' and completed_at is not null) then
    raise exception 'completed history lost'; end if;
  execute 'reset role';
  if not exists(select 1 from public.mentorship_ratings where session_id=v_completed_session and rating=5) then
    raise exception 'rating lost'; end if;
end $test$;
rollback;
select 'PASS: mentorship acceptance/schedule/read/cancel/reschedule authorization; fixtures rolled back' as result;
