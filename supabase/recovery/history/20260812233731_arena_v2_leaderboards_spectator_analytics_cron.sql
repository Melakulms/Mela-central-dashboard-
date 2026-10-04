-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812233731
create or replace function private.get_arena_leaderboard(p_scope text default 'global',p_period text default 'all_time',p_arena_type text default 'overall',p_career_path_id uuid default null,p_season_id uuid default null,p_limit integer default 50)
returns table(rank bigint,user_id uuid,full_name text,avatar_url text,rating integer,xp bigint,wins integer,matches_played integer,period_xp bigint)
language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=(select auth.uid()); v_university text; v_region text; v_start timestamptz;
begin
  if p_scope not in ('global','university','region','career_path','season') then raise exception 'invalid leaderboard scope'; end if;
  if p_period not in ('daily','weekly','monthly','all_time') then raise exception 'invalid leaderboard period'; end if;
  if p_arena_type not in ('overall','quiz_battle','speed_quiz','interview_practice','case_sprint','team_battle','skill_sprint','employer_challenge') then raise exception 'invalid arena type'; end if;
  if p_scope in ('university','region') and v_uid is null then raise exception 'authentication required for local leaderboard'; end if;
  if p_scope='career_path' and p_career_path_id is null then raise exception 'career_path_id required'; end if;
  if p_scope='season' and p_season_id is null then raise exception 'season_id required'; end if;
  select university,region into v_university,v_region from public.profiles where id=v_uid;
  v_start:=case p_period when 'daily' then date_trunc('day',now()) when 'weekly' then date_trunc('week',now()) when 'monthly' then date_trunc('month',now()) else null end;
  return query
  with base as (
    select r.user_id,p.full_name,p.avatar_url,r.rating,r.xp,r.wins,r.matches_played,
      case when p_period='all_time' then r.xp else coalesce((select sum(h.xp_awarded)::bigint from public.arena_rating_history h where h.user_id=r.user_id and h.arena_type=p_arena_type and h.created_at>=v_start),0) end period_xp
    from public.arena_player_ratings r join public.profiles p on p.id=r.user_id
    where r.arena_type=p_arena_type
      and (p_scope<>'university' or (v_university is not null and p.university=v_university))
      and (p_scope<>'region' or (v_region is not null and p.region=v_region))
      and (p_scope<>'career_path' or exists(select 1 from public.arena_rating_history h join public.arena_matches m on m.id=h.match_id where h.user_id=r.user_id and h.arena_type=p_arena_type and m.career_path_id=p_career_path_id))
      and (p_scope<>'season' or exists(select 1 from public.arena_rating_history h join public.arena_matches m on m.id=h.match_id where h.user_id=r.user_id and h.arena_type=p_arena_type and m.season_id=p_season_id))
  ), ranked as (
    select row_number() over(order by case when p_period='all_time' then rating else period_xp end desc,rating desc,xp desc,user_id) rank,* from base
  )
  select ranked.rank,ranked.user_id,ranked.full_name,ranked.avatar_url,ranked.rating,ranked.xp,ranked.wins,ranked.matches_played,ranked.period_xp from ranked order by ranked.rank limit greatest(1,least(coalesce(p_limit,50),100));
end $$;

create or replace function private.get_arena_live_scoreboard(p_match_id uuid)
returns table(rank bigint,user_id uuid,full_name text,avatar_url text,team_name text,score integer,placement integer,status text)
language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=(select auth.uid()); v_m public.arena_matches;
begin
  select * into v_m from public.arena_matches where id=p_match_id;
  if v_m.id is null then raise exception 'arena not found'; end if;
  if not (v_m.visibility='public' and v_m.status in ('live','completed')) and not (v_uid is not null and private.can_read_arena_match(p_match_id)) then raise exception 'arena scoreboard not available'; end if;
  return query
    select row_number() over(order by coalesce(ap.placement,2147483647),ap.score desc,ap.joined_at),ap.user_id,p.full_name,p.avatar_url,t.name,ap.score,ap.placement,ap.status
    from public.arena_participants ap join public.profiles p on p.id=ap.user_id left join public.arena_teams t on t.id=ap.team_id
    where ap.match_id=p_match_id and ap.status<>'withdrawn'
    order by coalesce(ap.placement,2147483647),ap.score desc,ap.joined_at;
end $$;

create or replace function private.get_arena_live_state(p_match_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=(select auth.uid()); v_m public.arena_matches; v_round jsonb; v_count integer;
begin
  select * into v_m from public.arena_matches where id=p_match_id;
  if v_m.id is null then raise exception 'arena not found'; end if;
  if not (v_m.visibility='public' and v_m.status in ('open','ready','live','completed')) and not (v_uid is not null and private.can_read_arena_match(p_match_id)) then raise exception 'arena not available'; end if;
  select jsonb_build_object('round_order',r.round_order,'title',r.title,'state',r.state,'starts_at',r.starts_at,'ends_at',r.ends_at,'time_limit_seconds',r.time_limit_seconds) into v_round from public.arena_rounds r where r.match_id=p_match_id and r.round_order=v_m.current_round_order;
  select count(*) into v_count from public.arena_participants where match_id=p_match_id and status<>'withdrawn';
  return jsonb_build_object('id',v_m.id,'title',v_m.title,'arena_type',v_m.arena_type,'status',v_m.status,'team_mode',v_m.team_mode,'rated',v_m.rated,'participant_count',v_count,'current_round',v_round,'round_ends_at',v_m.round_ends_at,'started_at',v_m.started_at,'ended_at',v_m.ended_at);
end $$;

create or replace function private.get_my_arena_stats()
returns jsonb language sql security definer set search_path='' as $$
select case when (select auth.uid()) is null then null else jsonb_build_object(
 'overall',(select to_jsonb(r) from (select rating,xp,level,matches_played,wins,losses,draws,current_streak,best_streak,last_match_at from public.arena_player_ratings where user_id=(select auth.uid()) and arena_type='overall') r),
 'ratings',coalesce((select jsonb_agg(to_jsonb(r) order by r.arena_type) from (select arena_type,rating,xp,level,matches_played,wins,losses,current_streak,best_streak from public.arena_player_ratings where user_id=(select auth.uid()) and arena_type<>'overall') r),'[]'::jsonb),
 'recent_matches',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (select h.match_id,h.arena_type,h.rating_delta,h.xp_awarded,h.placement,h.result,h.created_at from public.arena_rating_history h where h.user_id=(select auth.uid()) and h.arena_type='overall' order by h.created_at desc limit 10) x),'[]'::jsonb),
 'arena_achievements',(select count(*) from public.career_passport_achievements a where a.user_id=(select auth.uid()) and a.achievement_type='arena' and a.verified=true),
 'pending_cash_rewards',(select count(*) from public.arena_rewards r where r.beneficiary_user_id=(select auth.uid()) and r.reward_type='cash' and r.status in ('pending','available')),
 'matchmaking',(select to_jsonb(q) from (select id,arena_type,rating_snapshot,status,matched_match_id,created_at,expires_at from public.arena_matchmaking_queue where user_id=(select auth.uid()) order by created_at desc limit 1) q)
) end;
$$;

create or replace function private.get_my_arena_creator_analytics(p_days integer default 30)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=(select auth.uid()); v_since timestamptz;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  v_since:=now()-make_interval(days=>greatest(1,least(coalesce(p_days,30),365)));
  return jsonb_build_object(
    'matches_created',(select count(*) from public.arena_matches where creator_id=v_uid and created_at>=v_since),
    'matches_started',(select count(*) from public.arena_matches where creator_id=v_uid and started_at>=v_since),
    'matches_completed',(select count(*) from public.arena_matches where creator_id=v_uid and ended_at>=v_since and status='completed'),
    'unique_participants',(select count(distinct ap.user_id) from public.arena_participants ap join public.arena_matches m on m.id=ap.match_id where m.creator_id=v_uid and m.created_at>=v_since),
    'submissions',(select count(*) from public.arena_round_submissions s join public.arena_matches m on m.id=s.match_id where m.creator_id=v_uid and s.submitted_at>=v_since),
    'average_score',(select round(avg(ap.score)::numeric,2) from public.arena_participants ap join public.arena_matches m on m.id=ap.match_id where m.creator_id=v_uid and m.status='completed' and m.ended_at>=v_since),
    'tournaments',(select count(*) from public.arena_tournaments t where t.created_by=v_uid and t.created_at>=v_since)
  );
end $$;

create or replace function private.refresh_arena_daily_metrics(p_date date default current_date)
returns void language plpgsql security definer set search_path='' as $$
begin
  insert into public.arena_daily_metrics(metric_date,arena_type,matches_created,matches_started,matches_completed,unique_participants,submissions,average_score,updated_at)
  select p_date,t.arena_type,
    (select count(*) from public.arena_matches m where m.arena_type=t.arena_type and m.created_at>=p_date::timestamptz and m.created_at<(p_date+1)::timestamptz),
    (select count(*) from public.arena_matches m where m.arena_type=t.arena_type and m.started_at>=p_date::timestamptz and m.started_at<(p_date+1)::timestamptz),
    (select count(*) from public.arena_matches m where m.arena_type=t.arena_type and m.ended_at>=p_date::timestamptz and m.ended_at<(p_date+1)::timestamptz and m.status='completed'),
    (select count(distinct ap.user_id) from public.arena_participants ap join public.arena_matches m on m.id=ap.match_id where m.arena_type=t.arena_type and ap.joined_at>=p_date::timestamptz and ap.joined_at<(p_date+1)::timestamptz),
    (select count(*) from public.arena_round_submissions s join public.arena_matches m on m.id=s.match_id where m.arena_type=t.arena_type and s.submitted_at>=p_date::timestamptz and s.submitted_at<(p_date+1)::timestamptz),
    (select round(avg(ap.score)::numeric,2) from public.arena_participants ap join public.arena_matches m on m.id=ap.match_id where m.arena_type=t.arena_type and m.ended_at>=p_date::timestamptz and m.ended_at<(p_date+1)::timestamptz and m.status='completed'),now()
  from (select unnest(array['quiz_battle','speed_quiz','interview_practice','case_sprint','team_battle','skill_sprint','employer_challenge']) arena_type) t
  on conflict(metric_date,arena_type) do update set matches_created=excluded.matches_created,matches_started=excluded.matches_started,matches_completed=excluded.matches_completed,unique_participants=excluded.unique_participants,submissions=excluded.submissions,average_score=excluded.average_score,updated_at=now();
end $$;

create or replace function private.advance_arena_season_lifecycle()
returns integer language plpgsql security definer set search_path='' as $$
declare v_count integer:=0; v_n integer;
begin
  update public.arena_seasons set status='active',updated_at=now() where status='open' and starts_at is not null and starts_at<=now() and (ends_at is null or ends_at>now()); get diagnostics v_n=row_count; v_count:=v_count+v_n;
  update public.arena_seasons set status='completed',updated_at=now() where status in ('open','active') and ends_at is not null and ends_at<=now(); get diagnostics v_n=row_count; v_count:=v_count+v_n;
  return v_count;
end $$;

create or replace function public.get_arena_leaderboard(p_scope text default 'global',p_period text default 'all_time',p_arena_type text default 'overall',p_career_path_id uuid default null,p_season_id uuid default null,p_limit integer default 50)
returns table(rank bigint,user_id uuid,full_name text,avatar_url text,rating integer,xp bigint,wins integer,matches_played integer,period_xp bigint) language sql security invoker set search_path='' as $$ select * from private.get_arena_leaderboard(p_scope,p_period,p_arena_type,p_career_path_id,p_season_id,p_limit); $$;
create or replace function public.get_arena_live_scoreboard(p_match_id uuid) returns table(rank bigint,user_id uuid,full_name text,avatar_url text,team_name text,score integer,placement integer,status text) language sql security invoker set search_path='' as $$ select * from private.get_arena_live_scoreboard(p_match_id); $$;
create or replace function public.get_arena_live_state(p_match_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select private.get_arena_live_state(p_match_id); $$;
create or replace function public.get_my_arena_stats() returns jsonb language sql security invoker set search_path='' as $$ select private.get_my_arena_stats(); $$;
create or replace function public.get_my_arena_creator_analytics(p_days integer default 30) returns jsonb language sql security invoker set search_path='' as $$ select private.get_my_arena_creator_analytics(p_days); $$;

revoke execute on function private.get_arena_leaderboard(text,text,text,uuid,uuid,integer),private.get_arena_live_scoreboard(uuid),private.get_arena_live_state(uuid) from public;
grant execute on function private.get_arena_leaderboard(text,text,text,uuid,uuid,integer),private.get_arena_live_scoreboard(uuid),private.get_arena_live_state(uuid) to anon,authenticated;
revoke execute on function private.get_my_arena_stats(),private.get_my_arena_creator_analytics(integer) from public,anon;
grant execute on function private.get_my_arena_stats(),private.get_my_arena_creator_analytics(integer) to authenticated;
revoke execute on function private.refresh_arena_daily_metrics(date),private.advance_arena_season_lifecycle() from public,anon,authenticated;
revoke execute on function public.get_arena_leaderboard(text,text,text,uuid,uuid,integer),public.get_arena_live_scoreboard(uuid),public.get_arena_live_state(uuid) from public;
grant execute on function public.get_arena_leaderboard(text,text,text,uuid,uuid,integer),public.get_arena_live_scoreboard(uuid),public.get_arena_live_state(uuid) to anon,authenticated;
revoke execute on function public.get_my_arena_stats(),public.get_my_arena_creator_analytics(integer) from public,anon;
grant execute on function public.get_my_arena_stats(),public.get_my_arena_creator_analytics(integer) to authenticated;

do $$ declare r record; begin for r in select jobid from cron.job where jobname in ('mela-arena-round-lifecycle','mela-arena-matchmaking','mela-arena-metrics','mela-arena-season-lifecycle') loop perform cron.unschedule(r.jobid); end loop; end $$;
select cron.schedule('mela-arena-round-lifecycle','* * * * *','select private.advance_arena_rounds();');
select cron.schedule('mela-arena-matchmaking','* * * * *','select private.process_arena_matchmaking();');
select cron.schedule('mela-arena-metrics','*/30 * * * *','select private.refresh_arena_daily_metrics(current_date);');
select cron.schedule('mela-arena-season-lifecycle','*/10 * * * *','select private.advance_arena_season_lifecycle();');
;
