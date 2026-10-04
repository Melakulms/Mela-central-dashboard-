begin;
do $test$
declare
  v_mentor uuid := gen_random_uuid();
  v_mentee uuid := gen_random_uuid();
  v_outsider uuid := gen_random_uuid();
  v_session uuid := gen_random_uuid();
  blocked boolean;
  r public.mentorship_ratings%rowtype;
  avg_rating numeric;
  v_rating_count integer;
begin
  insert into auth.users(id,email,raw_app_meta_data,raw_user_meta_data,email_confirmed_at,created_at,updated_at)
  values
    (v_mentor,v_mentor::text||'@example.invalid','{"provider":"email"}','{"full_name":"Mentor fixture","role":"mentor"}',now(),now(),now()),
    (v_mentee,v_mentee::text||'@example.invalid','{"provider":"email"}','{"full_name":"Mentee fixture","role":"student"}',now(),now(),now()),
    (v_outsider,v_outsider::text||'@example.invalid','{"provider":"email"}','{"full_name":"Outsider fixture","role":"student"}',now(),now(),now());

  execute 'set local role service_role';
  insert into public.mentor_profiles(user_id,headline,expertise,verified,active,verified_at)
  values(v_mentor,'Fixture mentor',array['career'],true,true,now());
  insert into public.mentorship_sessions(id,mentor_id,mentee_id,scheduled_at,status,completed_at)
  values(v_session,v_mentor,v_mentee,now()-interval '1 hour','completed',now()-interval '30 minutes');
  execute 'reset role';

  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_mentee,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  select * into r from public.rate_mentorship_session(v_session,5::smallint,'Very useful session.'::text);
  if r.id is null or r.rating<>5 or r.mentee_id<>v_mentee or r.mentor_id<>v_mentor then
    raise exception 'valid mentorship rating was not recorded';
  end if;

  blocked:=false;
  begin
    perform public.rate_mentorship_session(v_session,4::smallint,'Duplicate attempt'::text);
  exception when others then blocked:=true;
  end;
  if not blocked then raise exception 'duplicate session rating was accepted'; end if;
  execute 'reset role';

  select rating_average,rating_count into avg_rating,v_rating_count from public.mentor_profiles where user_id=v_mentor;
  if avg_rating<>5.00 or v_rating_count<>1 then raise exception 'mentor rating aggregate did not refresh'; end if;

  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_outsider,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  if exists(select 1 from public.mentorship_ratings mr where mr.session_id=v_session) then
    raise exception 'outsider can read mentorship rating';
  end if;
  blocked:=false;
  begin
    perform public.rate_mentorship_session(v_session,1::smallint,'Unauthorized rating'::text);
  exception when others then blocked:=true;
  end;
  if not blocked then raise exception 'outsider could rate mentorship session'; end if;
  blocked:=false;
  begin
    insert into public.mentorship_ratings(session_id,mentor_id,mentee_id,rating) values(gen_random_uuid(),v_mentor,v_outsider,5);
  exception when insufficient_privilege then blocked:=true;
  end;
  if not blocked then raise exception 'authenticated user has direct rating insert privilege'; end if;
end
$test$;
rollback;
