-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812233509
alter table public.arena_matches alter column rated set default false;
alter table public.arena_matches add column if not exists career_path_id uuid references public.career_paths(id) on delete set null;
alter table public.arena_teams add column if not exists tournament_team_id uuid references public.arena_tournament_teams(id) on delete set null;
create index if not exists arena_matches_career_path_idx on public.arena_matches(career_path_id);
create index if not exists arena_teams_tournament_team_idx on public.arena_teams(tournament_team_id);

create or replace function private.ensure_arena_rating(p_user_id uuid, p_arena_type text)
returns integer language plpgsql security definer set search_path='' as $$
declare v_rating integer;
begin
  if p_arena_type not in ('overall','quiz_battle','speed_quiz','interview_practice','case_sprint','team_battle','skill_sprint','employer_challenge') then raise exception 'invalid arena rating type'; end if;
  insert into public.arena_player_ratings(user_id,arena_type) values(p_user_id,p_arena_type) on conflict do nothing;
  select rating into v_rating from public.arena_player_ratings where user_id=p_user_id and arena_type=p_arena_type;
  return coalesce(v_rating,1000);
end $$;

create or replace function private.process_arena_ratings(p_match_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare
  v_match public.arena_matches;
  v_count integer;
  p record;
  v_before integer;
  v_type_before integer;
  v_expected numeric;
  v_actual numeric;
  v_delta integer;
  v_xp integer;
  v_result text;
  v_new_xp bigint;
  v_new_level integer;
begin
  select * into v_match from public.arena_matches where id=p_match_id for update;
  if v_match.id is null or not v_match.rated or v_match.rating_processed_at is not null or v_match.status <> 'completed' then return; end if;
  select count(*) into v_count from public.arena_participants where match_id=p_match_id and status in ('finished','disqualified');
  if v_count < 2 then update public.arena_matches set rating_processed_at=now() where id=p_match_id; return; end if;

  for p in select ap.user_id,ap.placement,ap.integrity_status from public.arena_participants ap where ap.match_id=p_match_id and ap.status in ('finished','disqualified') loop
    v_before:=private.ensure_arena_rating(p.user_id,'overall');
    v_type_before:=private.ensure_arena_rating(p.user_id,v_match.arena_type);
    select avg(1.0/(1.0+power(10.0,(private.ensure_arena_rating(o.user_id,'overall')-v_before)/400.0))),
           avg(case when p.placement is null or o.placement is null then 0.5 when p.placement<o.placement then 1.0 when p.placement=o.placement then 0.5 else 0.0 end)
      into v_expected,v_actual
      from public.arena_participants o
     where o.match_id=p_match_id and o.user_id<>p.user_id and o.status in ('finished','disqualified');
    if p.integrity_status='disqualified' then v_delta:=-32; v_xp:=0; v_result:='loss';
    else
      v_delta:=greatest(-40,least(40,round(32*(coalesce(v_actual,0.5)-coalesce(v_expected,0.5)))::int));
      v_xp:=50 + case when p.placement=1 then 100 when p.placement=2 then 60 when p.placement=3 then 40 else 20 end;
      v_result:=case when v_count=2 and p.placement=1 then 'win' when v_count=2 then 'loss' else 'placement' end;
    end if;

    update public.arena_player_ratings r set
      rating=greatest(100,least(5000,r.rating+v_delta)),
      xp=r.xp+v_xp,
      level=greatest(1,floor(sqrt((r.xp+v_xp)/250.0))::int+1),
      matches_played=r.matches_played+1,
      wins=r.wins+case when p.placement=1 and p.integrity_status<>'disqualified' then 1 else 0 end,
      losses=r.losses+case when p.placement<>1 or p.integrity_status='disqualified' then 1 else 0 end,
      current_streak=case when p.placement=1 and p.integrity_status<>'disqualified' then r.current_streak+1 else 0 end,
      best_streak=greatest(r.best_streak,case when p.placement=1 and p.integrity_status<>'disqualified' then r.current_streak+1 else r.best_streak end),
      last_match_at=now(),updated_at=now()
    where r.user_id=p.user_id and r.arena_type='overall'
    returning xp,level into v_new_xp,v_new_level;

    update public.arena_player_ratings r set
      rating=greatest(100,least(5000,r.rating+v_delta)), xp=r.xp+v_xp,
      level=greatest(1,floor(sqrt((r.xp+v_xp)/250.0))::int+1), matches_played=r.matches_played+1,
      wins=r.wins+case when p.placement=1 and p.integrity_status<>'disqualified' then 1 else 0 end,
      losses=r.losses+case when p.placement<>1 or p.integrity_status='disqualified' then 1 else 0 end,
      current_streak=case when p.placement=1 and p.integrity_status<>'disqualified' then r.current_streak+1 else 0 end,
      best_streak=greatest(r.best_streak,case when p.placement=1 and p.integrity_status<>'disqualified' then r.current_streak+1 else r.best_streak end),
      last_match_at=now(),updated_at=now()
    where r.user_id=p.user_id and r.arena_type=v_match.arena_type;

    insert into public.arena_rating_history(match_id,user_id,arena_type,rating_before,rating_after,rating_delta,xp_awarded,placement,result)
    values(p_match_id,p.user_id,'overall',v_before,greatest(100,least(5000,v_before+v_delta)),v_delta,v_xp,p.placement,v_result) on conflict do nothing;
    insert into public.arena_rating_history(match_id,user_id,arena_type,rating_before,rating_after,rating_delta,xp_awarded,placement,result)
    values(p_match_id,p.user_id,v_match.arena_type,v_type_before,greatest(100,least(5000,v_type_before+v_delta)),v_delta,v_xp,p.placement,v_result) on conflict do nothing;

    update public.arena_participants set rating_before=v_before,rating_after=greatest(100,least(5000,v_before+v_delta)),rating_delta=v_delta,xp_awarded=v_xp,result=v_result where match_id=p_match_id and user_id=p.user_id;
  end loop;
  update public.arena_matches set rating_processed_at=now(),updated_at=now() where id=p_match_id;
end $$;

create or replace function private.assign_arena_judge(p_match_id uuid,p_user_id uuid,p_role text default 'judge')
returns void language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=(select auth.uid());
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if p_role not in ('judge','lead_judge') then raise exception 'invalid judge role'; end if;
  if not exists(select 1 from public.arena_matches m where m.id=p_match_id and (m.creator_id=v_uid or private.is_admin_user())) then raise exception 'arena creator access required'; end if;
  if not exists(select 1 from public.profiles where id=p_user_id) then raise exception 'judge not found'; end if;
  insert into public.arena_judges(match_id,user_id,assigned_by,judge_role,status) values(p_match_id,p_user_id,v_uid,p_role,'active')
  on conflict(match_id,user_id) do update set assigned_by=excluded.assigned_by,judge_role=excluded.judge_role,status='active',assigned_at=now();
  insert into public.notifications(user_id,title,body,ref_table,ref_id) values(p_user_id,'Arena judge assignment','You were assigned to judge an Arena.','arena_matches',p_match_id);
end $$;

create or replace function private.remove_arena_judge(p_match_id uuid,p_user_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=(select auth.uid());
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if not exists(select 1 from public.arena_matches m where m.id=p_match_id and (m.creator_id=v_uid or private.is_admin_user())) then raise exception 'arena creator access required'; end if;
  update public.arena_judges set status='removed' where match_id=p_match_id and user_id=p_user_id;
end $$;

create or replace function private.review_arena_submission(p_submission_id uuid,p_score numeric,p_feedback text)
returns public.arena_round_submissions language plpgsql security definer set search_path='' as $$
declare v public.arena_round_submissions; v_match uuid; v_max numeric; v_uid uuid:=(select auth.uid());
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select s.match_id,r.max_points into v_match,v_max from public.arena_round_submissions s join public.arena_rounds r on r.id=s.round_id where s.id=p_submission_id;
  if v_match is null or not exists(select 1 from public.arena_matches m where m.id=v_match and (m.creator_id=v_uid or private.is_admin_user() or exists(select 1 from public.arena_judges j where j.match_id=m.id and j.user_id=v_uid and j.status='active'))) then raise exception 'arena judge access required'; end if;
  if p_score<0 or p_score>v_max then raise exception 'score outside round range'; end if;
  update public.arena_round_submissions set score=p_score,feedback=left(p_feedback,4000),reviewed_by=v_uid,reviewed_at=now() where id=p_submission_id returning * into v;
  update public.arena_participants p set score=coalesce((select sum(coalesce(s.score,0))::int from public.arena_round_submissions s where s.match_id=v_match and s.user_id=p.user_id),0) where p.match_id=v_match;
  return v;
end $$;

create or replace function private.invite_arena_user(p_match_id uuid,p_user_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=(select auth.uid()); v_id uuid;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if p_user_id=v_uid then raise exception 'cannot invite yourself'; end if;
  if not exists(select 1 from public.arena_matches m where m.id=p_match_id and m.status in ('draft','open','ready') and (m.creator_id=v_uid or private.is_admin_user())) then raise exception 'arena creator access required'; end if;
  if exists(select 1 from public.arena_participants p where p.match_id=p_match_id and p.user_id=p_user_id and p.status<>'withdrawn') then raise exception 'user already participates'; end if;
  insert into public.arena_invites(match_id,invited_user_id,invited_by,status) values(p_match_id,p_user_id,v_uid,'pending') returning id into v_id;
  insert into public.notifications(user_id,title,body,ref_table,ref_id) values(p_user_id,'Arena invitation','You have been invited to an Arena.','arena_matches',p_match_id);
  return v_id;
end $$;

create or replace function private.respond_arena_invite(p_invite_id uuid,p_accept boolean)
returns void language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=(select auth.uid()); v_inv public.arena_invites; v_max integer; v_count integer;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select * into v_inv from public.arena_invites where id=p_invite_id and invited_user_id=v_uid and status='pending' for update;
  if v_inv.id is null then raise exception 'pending invitation not found'; end if;
  if not p_accept then update public.arena_invites set status='declined',responded_at=now() where id=p_invite_id; return; end if;
  select max_participants into v_max from public.arena_matches where id=v_inv.match_id and status in ('open','ready');
  if v_max is null then raise exception 'arena is not joinable'; end if;
  select count(*) into v_count from public.arena_participants where match_id=v_inv.match_id and status in ('joined','active','finished');
  if v_count>=v_max then raise exception 'arena is full'; end if;
  insert into public.arena_participants(match_id,user_id,status,ready) values(v_inv.match_id,v_uid,'joined',false) on conflict(match_id,user_id) do update set status='joined',ready=false,joined_at=now();
  update public.arena_invites set status='accepted',responded_at=now() where id=p_invite_id;
end $$;

create or replace function private.record_arena_integrity_event(p_match_id uuid,p_event_type text,p_round_id uuid default null,p_details jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=(select auth.uid()); v_severity smallint; v_count integer; v_weight integer; v_score numeric; v_status text;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if p_event_type not in ('tab_hidden','tab_visible','window_blur','window_focus','fullscreen_exit','fullscreen_enter','disconnect','reconnect','network_change','duplicate_session','suspicious_timing') then raise exception 'invalid integrity event'; end if;
  if pg_column_size(coalesce(p_details,'{}'::jsonb))>8192 then raise exception 'integrity event details too large'; end if;
  if not exists(select 1 from public.arena_matches m join public.arena_participants p on p.match_id=m.id where m.id=p_match_id and m.status='live' and p.user_id=v_uid and p.status='active') then raise exception 'active arena participation required'; end if;
  if p_round_id is not null and not exists(select 1 from public.arena_rounds where id=p_round_id and match_id=p_match_id) then raise exception 'round does not belong to arena'; end if;
  v_severity:=case p_event_type when 'duplicate_session' then 5 when 'suspicious_timing' then 4 when 'tab_hidden' then 2 when 'fullscreen_exit' then 2 when 'disconnect' then 2 when 'network_change' then 1 when 'window_blur' then 1 else 1 end;
  insert into public.arena_integrity_events(match_id,user_id,round_id,event_type,severity,details) values(p_match_id,v_uid,p_round_id,p_event_type,v_severity,coalesce(p_details,'{}'::jsonb));
  select count(*),coalesce(sum(severity),0) into v_count,v_weight from public.arena_integrity_events where match_id=p_match_id and user_id=v_uid and event_type in ('tab_hidden','window_blur','fullscreen_exit','disconnect','duplicate_session','suspicious_timing');
  v_score:=greatest(0,100-v_weight*5);
  v_status:=case when v_score<50 then 'flagged' when v_score<80 then 'review' else 'clear' end;
  insert into public.arena_integrity_summaries(match_id,user_id,event_count,weighted_events,integrity_score,status,updated_at) values(p_match_id,v_uid,v_count,v_weight,v_score,v_status,now())
  on conflict(match_id,user_id) do update set event_count=excluded.event_count,weighted_events=excluded.weighted_events,integrity_score=excluded.integrity_score,status=case when arena_integrity_summaries.status='disqualified' then 'disqualified' else excluded.status end,updated_at=now();
  update public.arena_participants set integrity_score=v_score,integrity_status=case when integrity_status='disqualified' then 'disqualified' else v_status end where match_id=p_match_id and user_id=v_uid;
  return jsonb_build_object('integrity_score',v_score,'status',v_status,'event_count',v_count);
end $$;

create or replace function private.review_arena_integrity(p_match_id uuid,p_user_id uuid,p_status text,p_notes text default null)
returns void language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=(select auth.uid());
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if p_status not in ('clear','review','flagged','disqualified') then raise exception 'invalid integrity status'; end if;
  if not exists(select 1 from public.arena_matches m where m.id=p_match_id and (m.creator_id=v_uid or private.is_admin_user() or exists(select 1 from public.arena_judges j where j.match_id=m.id and j.user_id=v_uid and j.status='active'))) then raise exception 'arena reviewer access required'; end if;
  insert into public.arena_integrity_summaries(match_id,user_id,status,reviewed_by,review_notes,reviewed_at,updated_at) values(p_match_id,p_user_id,p_status,v_uid,left(p_notes,4000),now(),now())
  on conflict(match_id,user_id) do update set status=excluded.status,reviewed_by=excluded.reviewed_by,review_notes=excluded.review_notes,reviewed_at=now(),updated_at=now();
  update public.arena_participants set integrity_status=p_status,status=case when p_status='disqualified' then 'disqualified' else status end where match_id=p_match_id and user_id=p_user_id;
end $$;

create or replace function private.join_arena_matchmaking(p_arena_type text,p_assessment_id uuid default null,p_career_path_id uuid default null,p_rating_range integer default 200)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=(select auth.uid()); v_rating integer; v_id uuid;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if p_arena_type not in ('quiz_battle','speed_quiz','interview_practice','case_sprint','skill_sprint') then raise exception 'unsupported matchmaking type'; end if;
  if p_arena_type in ('quiz_battle','speed_quiz') and p_assessment_id is null then raise exception 'assessment required for quiz matchmaking'; end if;
  if p_assessment_id is not null and not exists(select 1 from public.skill_assessments a where a.id=p_assessment_id and a.status='published') then raise exception 'published assessment not found'; end if;
  if exists(select 1 from public.arena_matchmaking_queue where user_id=v_uid and status='waiting') then raise exception 'already in matchmaking queue'; end if;
  v_rating:=private.ensure_arena_rating(v_uid,p_arena_type);
  insert into public.arena_matchmaking_queue(user_id,arena_type,assessment_id,career_path_id,rating_snapshot,rating_range,status) values(v_uid,p_arena_type,p_assessment_id,p_career_path_id,v_rating,greatest(50,least(coalesce(p_rating_range,200),1000)),'waiting') returning id into v_id;
  perform private.process_arena_matchmaking();
  return v_id;
end $$;

create or replace function private.cancel_arena_matchmaking()
returns void language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=(select auth.uid());
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  update public.arena_matchmaking_queue set status='cancelled' where user_id=v_uid and status='waiting';
end $$;

create or replace function private.process_arena_matchmaking()
returns integer language plpgsql security definer set search_path='' as $$
declare q1 record; q2 record; v_match uuid; v_count integer:=0; v_round_type text; v_prompt text;
begin
  update public.arena_matchmaking_queue set status='expired' where status='waiting' and expires_at<=now();
  for q1 in select * from public.arena_matchmaking_queue q where q.status='waiting' and q.expires_at>now() order by q.created_at for update skip locked loop
    select q.* into q2 from public.arena_matchmaking_queue q where q.status='waiting' and q.id<>q1.id and q.user_id<>q1.user_id and q.arena_type=q1.arena_type and q.assessment_id is not distinct from q1.assessment_id and q.expires_at>now() and abs(q.rating_snapshot-q1.rating_snapshot)<=least(q.rating_range,q1.rating_range) order by abs(q.rating_snapshot-q1.rating_snapshot),q.created_at limit 1 for update skip locked;
    if q2.id is null then continue; end if;
    insert into public.arena_matches(title,description,arena_type,creator_id,visibility,assessment_id,career_path_id,min_participants,max_participants,team_mode,status,scoring_mode,rated,integrity_required,rules)
    values('Mela Matchmaking '||replace(initcap(replace(q1.arena_type,'_',' ')),'  ',' '),'Matched by Mela based on Arena rating.',q1.arena_type,q1.user_id,'private',q1.assessment_id,coalesce(q1.career_path_id,q2.career_path_id),2,2,false,'open',case when q1.arena_type in ('quiz_battle','speed_quiz') then 'auto' else 'judge' end,true,q1.arena_type in ('quiz_battle','speed_quiz'),jsonb_build_object('matchmaking',true)) returning id into v_match;
    insert into public.arena_participants(match_id,user_id,status,ready) values(v_match,q1.user_id,'joined',false),(v_match,q2.user_id,'joined',false);
    if q1.arena_type not in ('quiz_battle','speed_quiz') then
      v_round_type:=case q1.arena_type when 'interview_practice' then 'interview' when 'case_sprint' then 'case' else 'task' end;
      v_prompt:=case q1.arena_type when 'interview_practice' then 'Respond to the interview prompt and demonstrate structured communication.' when 'case_sprint' then 'Analyze the case, state assumptions, and submit a concise recommendation.' else 'Complete the skill sprint task and submit your work.' end;
      insert into public.arena_rounds(match_id,round_order,round_type,title,prompt,max_points,time_limit_seconds,state) values(v_match,1,v_round_type,'Round 1',v_prompt,100,900,'planned');
    end if;
    update public.arena_matchmaking_queue set status='matched',matched_match_id=v_match where id in (q1.id,q2.id);
    insert into public.notifications(user_id,title,body,ref_table,ref_id) values(q1.user_id,'Arena match found','Your Arena opponent is ready.','arena_matches',v_match),(q2.user_id,'Arena match found','Your Arena opponent is ready.','arena_matches',v_match);
    v_count:=v_count+1;
  end loop;
  return v_count;
end $$;

create or replace function private.start_arena(p_match_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare v_m public.arena_matches; v_first public.arena_rounds; v_now timestamptz:=now();
begin
  select * into v_m from public.arena_matches where id=p_match_id for update;
  if v_m.id is null or (v_m.creator_id<>(select auth.uid()) and not private.is_admin_user()) then raise exception 'arena creator access required'; end if;
  if v_m.status not in ('open','ready') then raise exception 'arena cannot start'; end if;
  if (select count(*) from public.arena_participants where match_id=p_match_id and status='joined')<v_m.min_participants then raise exception 'not enough participants'; end if;
  if v_m.assessment_id is not null and v_m.arena_type in ('quiz_battle','speed_quiz') and not exists(select 1 from public.arena_rounds where match_id=p_match_id) then
    insert into public.arena_rounds(match_id,round_order,round_type,title,prompt,assessment_question_id,max_points,time_limit_seconds,state)
    select p_match_id,row_number() over(order by q.question_order),'quiz','Question '||row_number() over(order by q.question_order),q.prompt,q.id,q.points,case when v_m.arena_type='speed_quiz' then 45 else 90 end,'planned'
    from public.assessment_questions q where q.assessment_id=v_m.assessment_id and q.active=true order by q.question_order limit 20;
  end if;
  if not exists(select 1 from public.arena_rounds where match_id=p_match_id) then raise exception 'arena needs at least one round'; end if;
  update public.arena_rounds set state='planned',starts_at=null,ends_at=null,opened_at=null,closed_at=null where match_id=p_match_id;
  select * into v_first from public.arena_rounds where match_id=p_match_id order by round_order limit 1;
  update public.arena_rounds set state='open',starts_at=v_now,opened_at=v_now,ends_at=v_now+make_interval(secs=>coalesce(v_first.time_limit_seconds,300)) where id=v_first.id;
  update public.arena_matches set status='live',started_at=v_now,current_round_order=v_first.round_order,round_started_at=v_now,round_ends_at=v_now+make_interval(secs=>coalesce(v_first.time_limit_seconds,300)),updated_at=v_now where id=p_match_id;
  update public.arena_participants set status='active' where match_id=p_match_id and status='joined';
end $$;

create or replace function private.finalize_arena_match(p_match_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare v_m public.arena_matches;
begin
  select * into v_m from public.arena_matches where id=p_match_id for update;
  if v_m.id is null or v_m.status='completed' then return; end if;
  if v_m.team_mode then
    with team_scores as (select p.team_id,sum(coalesce(p.score,0)) s,min(p.joined_at) j from public.arena_participants p where p.match_id=p_match_id and p.team_id is not null and p.status in ('active','finished','disqualified') group by p.team_id), ranked as (select team_id,dense_rank() over(order by s desc,j asc) placement from team_scores)
    update public.arena_participants p set placement=r.placement,status=case when p.status='disqualified' then 'disqualified' else 'finished' end,finished_at=coalesce(p.finished_at,now()) from ranked r where p.match_id=p_match_id and p.team_id=r.team_id;
  else
    with ranked as (select user_id,row_number() over(order by score desc,joined_at asc) rn from public.arena_participants where match_id=p_match_id and status in ('active','finished','disqualified'))
    update public.arena_participants p set placement=r.rn,status=case when p.status='disqualified' then 'disqualified' else 'finished' end,finished_at=coalesce(p.finished_at,now()) from ranked r where p.match_id=p_match_id and p.user_id=r.user_id;
  end if;
  update public.arena_rounds set state=case when state='open' then 'closed' else state end,closed_at=case when state='open' then now() else closed_at end where match_id=p_match_id;
  update public.arena_matches set status='completed',ended_at=now(),round_ends_at=null,updated_at=now() where id=p_match_id;
  perform private.process_arena_ratings(p_match_id);
end $$;

create or replace function private.finish_arena(p_match_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
  if not exists(select 1 from public.arena_matches m where m.id=p_match_id and (m.creator_id=(select auth.uid()) or private.is_admin_user())) then raise exception 'arena creator access required'; end if;
  perform private.finalize_arena_match(p_match_id);
end $$;

create or replace function private.advance_arena_rounds()
returns integer language plpgsql security definer set search_path='' as $$
declare m record; v_next public.arena_rounds; v_now timestamptz:=now(); v_count integer:=0;
begin
  for m in select * from public.arena_matches where status='live' and round_ends_at is not null and round_ends_at<=v_now for update skip locked loop
    update public.arena_rounds set state='closed',closed_at=v_now where match_id=m.id and round_order=m.current_round_order and state='open';
    select * into v_next from public.arena_rounds where match_id=m.id and round_order>m.current_round_order order by round_order limit 1;
    if v_next.id is null then perform private.finalize_arena_match(m.id);
    else
      update public.arena_rounds set state='open',starts_at=v_now,opened_at=v_now,ends_at=v_now+make_interval(secs=>coalesce(v_next.time_limit_seconds,300)) where id=v_next.id;
      update public.arena_matches set current_round_order=v_next.round_order,round_started_at=v_now,round_ends_at=v_now+make_interval(secs=>coalesce(v_next.time_limit_seconds,300)),updated_at=v_now where id=m.id;
    end if;
    v_count:=v_count+1;
  end loop;
  return v_count;
end $$;

create or replace function public.assign_arena_judge(p_match_id uuid,p_user_id uuid,p_role text default 'judge') returns void language sql security invoker set search_path='' as $$ select private.assign_arena_judge(p_match_id,p_user_id,p_role); $$;
create or replace function public.remove_arena_judge(p_match_id uuid,p_user_id uuid) returns void language sql security invoker set search_path='' as $$ select private.remove_arena_judge(p_match_id,p_user_id); $$;
create or replace function public.invite_arena_user(p_match_id uuid,p_user_id uuid) returns uuid language sql security invoker set search_path='' as $$ select private.invite_arena_user(p_match_id,p_user_id); $$;
create or replace function public.respond_arena_invite(p_invite_id uuid,p_accept boolean) returns void language sql security invoker set search_path='' as $$ select private.respond_arena_invite(p_invite_id,p_accept); $$;
create or replace function public.record_arena_integrity_event(p_match_id uuid,p_event_type text,p_round_id uuid default null,p_details jsonb default '{}'::jsonb) returns jsonb language sql security invoker set search_path='' as $$ select private.record_arena_integrity_event(p_match_id,p_event_type,p_round_id,p_details); $$;
create or replace function public.review_arena_integrity(p_match_id uuid,p_user_id uuid,p_status text,p_notes text default null) returns void language sql security invoker set search_path='' as $$ select private.review_arena_integrity(p_match_id,p_user_id,p_status,p_notes); $$;
create or replace function public.join_arena_matchmaking(p_arena_type text,p_assessment_id uuid default null,p_career_path_id uuid default null,p_rating_range integer default 200) returns uuid language sql security invoker set search_path='' as $$ select private.join_arena_matchmaking(p_arena_type,p_assessment_id,p_career_path_id,p_rating_range); $$;
create or replace function public.cancel_arena_matchmaking() returns void language sql security invoker set search_path='' as $$ select private.cancel_arena_matchmaking(); $$;

revoke execute on function private.ensure_arena_rating(uuid,text),private.process_arena_ratings(uuid),private.process_arena_matchmaking(),private.advance_arena_rounds(),private.finalize_arena_match(uuid) from public,anon,authenticated;
revoke execute on function private.assign_arena_judge(uuid,uuid,text),private.remove_arena_judge(uuid,uuid),private.invite_arena_user(uuid,uuid),private.respond_arena_invite(uuid,boolean),private.record_arena_integrity_event(uuid,text,uuid,jsonb),private.review_arena_integrity(uuid,uuid,text,text),private.join_arena_matchmaking(text,uuid,uuid,integer),private.cancel_arena_matchmaking() from public,anon;
grant execute on function private.assign_arena_judge(uuid,uuid,text),private.remove_arena_judge(uuid,uuid),private.invite_arena_user(uuid,uuid),private.respond_arena_invite(uuid,boolean),private.record_arena_integrity_event(uuid,text,uuid,jsonb),private.review_arena_integrity(uuid,uuid,text,text),private.join_arena_matchmaking(text,uuid,uuid,integer),private.cancel_arena_matchmaking() to authenticated;
revoke execute on function public.assign_arena_judge(uuid,uuid,text),public.remove_arena_judge(uuid,uuid),public.invite_arena_user(uuid,uuid),public.respond_arena_invite(uuid,boolean),public.record_arena_integrity_event(uuid,text,uuid,jsonb),public.review_arena_integrity(uuid,uuid,text,text),public.join_arena_matchmaking(text,uuid,uuid,integer),public.cancel_arena_matchmaking() from public,anon;
grant execute on function public.assign_arena_judge(uuid,uuid,text),public.remove_arena_judge(uuid,uuid),public.invite_arena_user(uuid,uuid),public.respond_arena_invite(uuid,boolean),public.record_arena_integrity_event(uuid,text,uuid,jsonb),public.review_arena_integrity(uuid,uuid,text,text),public.join_arena_matchmaking(text,uuid,uuid,integer),public.cancel_arena_matchmaking() to authenticated;
;
