-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812221634
-- Opportunity Hub: let candidates consume their own generated matches safely.
drop policy if exists "Candidates read own opportunity matches" on public.candidate_matches;
create policy "Candidates read own opportunity matches" on public.candidate_matches for select to authenticated
using (
  candidate_id=(select auth.uid())
  and (opportunity_id is null or exists(select 1 from public.opportunities o where o.id=opportunity_id and o.status='open' and o.verified_active=true and o.deadline>=current_date))
);

grant select on public.candidate_matches to authenticated;

create or replace function public.refresh_my_opportunity_matches()
returns integer language plpgsql security invoker set search_path=''
as $$ declare v_uid uuid:=(select auth.uid()); v_count int; begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if not exists(select 1 from public.profiles p where p.id=v_uid and p.role='student'::public.user_role) then raise exception 'student/talent profile required'; end if;
  perform private.refresh_matches_for_user(v_uid);
  select count(*) into v_count from public.candidate_matches where candidate_id=v_uid;
  return v_count;
end $$;
revoke all on function public.refresh_my_opportunity_matches() from public,anon;
grant execute on function public.refresh_my_opportunity_matches() to authenticated,service_role;

create or replace function public.get_my_opportunity_matches(p_limit integer default 25,p_type public.opportunity_type default null)
returns table(opportunity_id uuid,title text,organization_name text,opportunity_type public.opportunity_type,deadline date,match_score numeric,matched_skills text[],missing_skills text[],reasons jsonb)
language sql stable security invoker set search_path=''
as $$
  select o.id,o.title,o.organization_name,o.opportunity_type,o.deadline,m.match_score,m.matched_skills,m.missing_skills,m.reasons
  from public.candidate_matches m join public.opportunities o on o.id=m.opportunity_id
  where m.candidate_id=(select auth.uid()) and o.status='open' and o.verified_active=true and o.deadline>=current_date
    and (p_type is null or o.opportunity_type=p_type)
  order by m.match_score desc,o.deadline asc
  limit greatest(1,least(coalesce(p_limit,25),100));
$$;
revoke all on function public.get_my_opportunity_matches(integer,public.opportunity_type) from public,anon;
grant execute on function public.get_my_opportunity_matches(integer,public.opportunity_type) to authenticated,service_role;

-- Scholarship Connect: ranked signed-in user's scholarship feed.
create or replace function public.get_my_scholarship_matches(p_limit integer default 25)
returns table(opportunity_id uuid,title text,institution text,study_country text,funding_type text,deadline date,eligibility_score integer,eligible boolean,checks jsonb)
language sql stable security invoker set search_path=''
as $$
  select o.id,o.title,s.institution,s.study_country,s.funding_type,o.deadline,
         coalesce((e.j->>'score')::int,0),coalesce((e.j->>'eligible')::boolean,false),coalesce(e.j->'checks','[]'::jsonb)
  from public.opportunities o
  join public.scholarship_details s on s.opportunity_id=o.id
  cross join lateral (select public.check_scholarship_eligibility(o.id) as j) e
  where o.opportunity_type='scholarships'::public.opportunity_type and o.status='open' and o.verified_active=true and o.deadline>=current_date
  order by coalesce((e.j->>'eligible')::boolean,false) desc,coalesce((e.j->>'score')::int,0) desc,o.deadline asc
  limit greatest(1,least(coalesce(p_limit,25),100));
$$;
revoke all on function public.get_my_scholarship_matches(integer) from public,anon;
grant execute on function public.get_my_scholarship_matches(integer) to authenticated,service_role;

-- Sponsored Challenges: controlled judge assignment/removal and lifecycle automation.
create or replace function private.assign_challenge_judge(p_challenge_id uuid,p_user_id uuid)
returns void language plpgsql security definer set search_path=''
as $$ begin
  if not private.has_challenge_manage_access(p_challenge_id) then raise exception 'challenge management access required'; end if;
  if not exists(select 1 from public.profiles where id=p_user_id) then raise exception 'judge profile not found'; end if;
  insert into public.challenge_judges(challenge_id,user_id,assigned_by) values(p_challenge_id,p_user_id,(select auth.uid())) on conflict(challenge_id,user_id) do nothing;
  perform private.create_notification(p_user_id,'Challenge judge assignment','You have been assigned as a judge for a Mela sponsored challenge.','sponsored_challenges',p_challenge_id);
end $$;
create or replace function public.assign_challenge_judge(p_challenge_id uuid,p_user_id uuid) returns void language sql security invoker set search_path='' as $$ select private.assign_challenge_judge(p_challenge_id,p_user_id); $$;

create or replace function private.remove_challenge_judge(p_challenge_id uuid,p_user_id uuid)
returns void language plpgsql security definer set search_path=''
as $$ begin
  if not private.has_challenge_manage_access(p_challenge_id) then raise exception 'challenge management access required'; end if;
  if exists(select 1 from public.challenge_reviews r join public.challenge_submissions s on s.id=r.submission_id where s.challenge_id=p_challenge_id and r.judge_id=p_user_id) then raise exception 'judge already submitted reviews; remove is blocked for audit integrity'; end if;
  delete from public.challenge_judges where challenge_id=p_challenge_id and user_id=p_user_id;
end $$;
create or replace function public.remove_challenge_judge(p_challenge_id uuid,p_user_id uuid) returns void language sql security invoker set search_path='' as $$ select private.remove_challenge_judge(p_challenge_id,p_user_id); $$;

create or replace function private.advance_sponsored_challenge_lifecycle()
returns integer language plpgsql security definer set search_path=''
as $$ declare v_count int:=0; v_n int; begin
  update public.sponsored_challenges set status='open',updated_at=now() where status='published' and (starts_at is null or starts_at<=now()) and (ends_at is null or ends_at>now()); get diagnostics v_n=row_count; v_count:=v_count+v_n;
  update public.sponsored_challenges set status='judging',updated_at=now() where status in ('published','open') and ends_at is not null and ends_at<=now(); get diagnostics v_n=row_count; v_count:=v_count+v_n;
  return v_count;
end $$;
do $$ declare v_job bigint; begin
  select jobid into v_job from cron.job where jobname='mela-sponsored-challenge-lifecycle' limit 1;
  if v_job is not null then perform cron.unschedule(v_job); end if;
  perform cron.schedule('mela-sponsored-challenge-lifecycle','*/10 * * * *','select private.advance_sponsored_challenge_lifecycle();');
end $$;

-- Arena teams: invitation code based create/join workflow.
alter table public.arena_teams add column if not exists join_code text;
update public.arena_teams set join_code=upper(substr(md5(id::text||created_at::text),1,10)) where join_code is null;
create unique index if not exists arena_teams_join_code_uidx on public.arena_teams(join_code) where join_code is not null;

create or replace function private.create_arena_team(p_match_id uuid,p_name text)
returns public.arena_teams language plpgsql security definer set search_path=''
as $$ declare v_uid uuid:=(select auth.uid()); v_m public.arena_matches; v public.arena_teams; begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select * into v_m from public.arena_matches where id=p_match_id for update;
  if v_m.id is null or not v_m.team_mode or v_m.status not in ('open','ready') then raise exception 'joinable team arena required'; end if;
  if not exists(select 1 from public.arena_participants where match_id=p_match_id and user_id=v_uid and status='joined') then perform private.join_arena(p_match_id); end if;
  if exists(select 1 from public.arena_participants where match_id=p_match_id and user_id=v_uid and team_id is not null) then raise exception 'already assigned to an arena team'; end if;
  insert into public.arena_teams(match_id,name,captain_id,join_code) values(p_match_id,p_name,v_uid,upper(substr(md5(gen_random_uuid()::text),1,10))) returning * into v;
  insert into public.arena_team_members(team_id,user_id) values(v.id,v_uid);
  update public.arena_participants set team_id=v.id where match_id=p_match_id and user_id=v_uid;
  return v;
end $$;
create or replace function public.create_arena_team(p_match_id uuid,p_name text) returns public.arena_teams language sql security invoker set search_path='' as $$ select private.create_arena_team(p_match_id,p_name); $$;

create or replace function private.join_arena_team(p_join_code text)
returns public.arena_teams language plpgsql security definer set search_path=''
as $$ declare v_uid uuid:=(select auth.uid()); v public.arena_teams; v_m public.arena_matches; begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select * into v from public.arena_teams where join_code=upper(trim(p_join_code));
  if v.id is null then raise exception 'arena team not found'; end if;
  select * into v_m from public.arena_matches where id=v.match_id for update;
  if not v_m.team_mode or v_m.status not in ('open','ready') then raise exception 'arena team is not joinable'; end if;
  if not exists(select 1 from public.arena_participants where match_id=v.match_id and user_id=v_uid and status='joined') then perform private.join_arena(v.match_id); end if;
  if exists(select 1 from public.arena_participants where match_id=v.match_id and user_id=v_uid and team_id is not null and team_id<>v.id) then raise exception 'already assigned to another team'; end if;
  if (select count(*) from public.arena_team_members where team_id=v.id)>=greatest(2,ceil(v_m.max_participants::numeric/2)::int) then raise exception 'arena team is full'; end if;
  insert into public.arena_team_members(team_id,user_id) values(v.id,v_uid) on conflict do nothing;
  update public.arena_participants set team_id=v.id where match_id=v.match_id and user_id=v_uid;
  return v;
end $$;
create or replace function public.join_arena_team(p_join_code text) returns public.arena_teams language sql security invoker set search_path='' as $$ select private.join_arena_team(p_join_code); $$;

-- Video call recording consent workflow.
alter table public.video_call_participants
  add column if not exists recording_consent boolean,
  add column if not exists recording_consented_at timestamptz;

create or replace function private.request_video_call_recording(p_room_id uuid)
returns void language plpgsql security definer set search_path=''
as $$ declare v_uid uuid:=(select auth.uid()); r record; begin
  if not exists(select 1 from public.video_call_participants p where p.room_id=p_room_id and p.user_id=v_uid and p.participant_role='host' and p.status in ('accepted','joined')) and not private.is_admin_user() then raise exception 'call host access required'; end if;
  update public.video_call_rooms set recording_status='requested',updated_at=now() where id=p_room_id and status in ('open','live','scheduled');
  update public.video_call_participants set recording_consent=null,recording_consented_at=null where room_id=p_room_id and status in ('accepted','joined');
  update public.video_call_participants set recording_consent=true,recording_consented_at=now() where room_id=p_room_id and user_id=v_uid;
  insert into public.video_call_events(room_id,actor_id,event_type) values(p_room_id,v_uid,'recording_requested');
  for r in select user_id from public.video_call_participants where room_id=p_room_id and user_id<>v_uid and status in ('accepted','joined') loop
    perform private.create_notification(r.user_id,'Recording consent requested','The host requested permission to record this Mela video call.','video_call_rooms',p_room_id);
  end loop;
end $$;
create or replace function public.request_video_call_recording(p_room_id uuid) returns void language sql security invoker set search_path='' as $$ select private.request_video_call_recording(p_room_id); $$;

create or replace function private.respond_video_call_recording_consent(p_room_id uuid,p_consent boolean)
returns void language plpgsql security definer set search_path=''
as $$ declare v_uid uuid:=(select auth.uid()); begin
  if not exists(select 1 from public.video_call_rooms where id=p_room_id and recording_status in ('requested','consented')) then raise exception 'recording consent is not pending'; end if;
  update public.video_call_participants set recording_consent=p_consent,recording_consented_at=now() where room_id=p_room_id and user_id=v_uid and status in ('accepted','joined');
  if not found then raise exception 'call participant access required'; end if;
  insert into public.video_call_events(room_id,actor_id,event_type,details) values(p_room_id,v_uid,'recording_consented',jsonb_build_object('consent',p_consent));
  if not exists(select 1 from public.video_call_participants where room_id=p_room_id and status in ('accepted','joined') and recording_consent is distinct from true) then update public.video_call_rooms set recording_status='consented',updated_at=now() where id=p_room_id; end if;
end $$;
create or replace function public.respond_video_call_recording_consent(p_room_id uuid,p_consent boolean) returns void language sql security invoker set search_path='' as $$ select private.respond_video_call_recording_consent(p_room_id,p_consent); $$;

create or replace function private.start_video_call_recording(p_room_id uuid)
returns void language plpgsql security definer set search_path=''
as $$ declare v_uid uuid:=(select auth.uid()); begin
  if not exists(select 1 from public.video_call_participants where room_id=p_room_id and user_id=v_uid and participant_role='host' and status='joined') and not private.is_admin_user() then raise exception 'joined call host required'; end if;
  if exists(select 1 from public.video_call_participants where room_id=p_room_id and status in ('accepted','joined') and recording_consent is distinct from true) then raise exception 'all current participants must consent before recording starts'; end if;
  update public.video_call_rooms set recording_status='recording',updated_at=now() where id=p_room_id and recording_status='consented';
  if not found then raise exception 'recording is not ready to start'; end if;
  insert into public.video_call_events(room_id,actor_id,event_type) values(p_room_id,v_uid,'recording_started');
end $$;
create or replace function public.start_video_call_recording(p_room_id uuid) returns void language sql security invoker set search_path='' as $$ select private.start_video_call_recording(p_room_id); $$;

create or replace function private.complete_video_call_recording(p_room_id uuid,p_recording_path text)
returns void language plpgsql security definer set search_path=''
as $$ declare v_uid uuid:=(select auth.uid()); begin
  if not exists(select 1 from public.video_call_participants where room_id=p_room_id and user_id=v_uid and participant_role='host') and not private.is_admin_user() then raise exception 'call host access required'; end if;
  if nullif(trim(coalesce(p_recording_path,'')),'') is null or p_recording_path not like p_room_id::text||'/%' then raise exception 'recording path must be stored under the room folder'; end if;
  update public.video_call_rooms set recording_status='completed',recording_path=p_recording_path,updated_at=now() where id=p_room_id and recording_status='recording';
  if not found then raise exception 'recording is not active'; end if;
  insert into public.video_call_events(room_id,actor_id,event_type,details) values(p_room_id,v_uid,'recording_stopped',jsonb_build_object('path',p_recording_path));
end $$;
create or replace function public.complete_video_call_recording(p_room_id uuid,p_recording_path text) returns void language sql security invoker set search_path='' as $$ select private.complete_video_call_recording(p_room_id,p_recording_path); $$;

-- Grants for newly exposed wrappers and private implementations.
do $$ declare r record; begin
  for r in select n.nspname,p.proname,pg_get_function_identity_arguments(p.oid) args from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where (n.nspname='public' and p.proname in ('assign_challenge_judge','remove_challenge_judge','create_arena_team','join_arena_team','request_video_call_recording','respond_video_call_recording_consent','start_video_call_recording','complete_video_call_recording'))
     or (n.nspname='private' and p.proname in ('assign_challenge_judge','remove_challenge_judge','create_arena_team','join_arena_team','request_video_call_recording','respond_video_call_recording_consent','start_video_call_recording','complete_video_call_recording')) loop
    execute format('revoke all on function %I.%I(%s) from public,anon',r.nspname,r.proname,r.args);
    execute format('grant execute on function %I.%I(%s) to authenticated,service_role',r.nspname,r.proname,r.args);
  end loop;
end $$;

;
