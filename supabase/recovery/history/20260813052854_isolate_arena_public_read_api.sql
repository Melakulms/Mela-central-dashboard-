-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260813052854
create schema if not exists arena_read;
revoke all on schema arena_read from public;
grant usage on schema arena_read to anon,authenticated,service_role;

create or replace function arena_read.get_live_state(p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_m public.arena_matches;
  v_round jsonb;
  v_count integer;
begin
  select * into v_m from public.arena_matches where id=p_match_id;
  if v_m.id is null then raise exception 'arena not found'; end if;
  if not (v_m.visibility='public' and v_m.status in ('open','ready','live','completed'))
     and not (v_uid is not null and private.can_read_arena_match(p_match_id)) then
    raise exception 'arena not available';
  end if;
  select jsonb_build_object(
    'round_order',r.round_order,'title',r.title,'state',r.state,
    'starts_at',r.starts_at,'ends_at',r.ends_at,'time_limit_seconds',r.time_limit_seconds
  ) into v_round
  from public.arena_rounds r
  where r.match_id=p_match_id and r.round_order=v_m.current_round_order;
  select count(*) into v_count from public.arena_participants where match_id=p_match_id and status<>'withdrawn';
  return jsonb_build_object(
    'id',v_m.id,'title',v_m.title,'arena_type',v_m.arena_type,'status',v_m.status,
    'team_mode',v_m.team_mode,'rated',v_m.rated,'participant_count',v_count,
    'current_round',v_round,'round_ends_at',v_m.round_ends_at,
    'started_at',v_m.started_at,'ended_at',v_m.ended_at
  );
end
$$;

create or replace function arena_read.get_live_scoreboard(p_match_id uuid)
returns table(rank bigint,user_id uuid,full_name text,avatar_url text,team_name text,score integer,placement integer,status text)
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_m public.arena_matches;
begin
  select * into v_m from public.arena_matches where id=p_match_id;
  if v_m.id is null then raise exception 'arena not found'; end if;
  if not (v_m.visibility='public' and v_m.status in ('live','completed'))
     and not (v_uid is not null and private.can_read_arena_match(p_match_id)) then
    raise exception 'arena scoreboard not available';
  end if;
  return query
  select row_number() over(order by coalesce(ap.placement,2147483647),ap.score desc,ap.joined_at),
         ap.user_id,p.full_name,p.avatar_url,t.name,ap.score,ap.placement,ap.status
    from public.arena_participants ap
    join public.profiles p on p.id=ap.user_id
    left join public.arena_teams t on t.id=ap.team_id
   where ap.match_id=p_match_id and ap.status<>'withdrawn'
   order by coalesce(ap.placement,2147483647),ap.score desc,ap.joined_at;
end
$$;

create or replace function arena_read.get_leaderboard(
  p_scope text default 'global',p_period text default 'all_time',p_arena_type text default 'overall',
  p_career_path_id uuid default null,p_season_id uuid default null,p_limit integer default 50
)
returns table(rank bigint,user_id uuid,full_name text,avatar_url text,rating integer,xp bigint,wins integer,matches_played integer,period_xp bigint)
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_university text;
  v_region text;
  v_start timestamptz;
begin
  if p_scope not in ('global','university','region','career_path','season') then raise exception 'invalid leaderboard scope'; end if;
  if p_period not in ('daily','weekly','monthly','all_time') then raise exception 'invalid leaderboard period'; end if;
  if p_arena_type not in ('overall','quiz_battle','speed_quiz','interview_practice','case_sprint','team_battle','skill_sprint','employer_challenge') then raise exception 'invalid arena type'; end if;
  if p_scope in ('university','region') and v_uid is null then raise exception 'authentication required for local leaderboard'; end if;
  if p_scope='career_path' and p_career_path_id is null then raise exception 'career_path_id required'; end if;
  if p_scope='season' and p_season_id is null then raise exception 'season_id required'; end if;
  if p_scope='season' and not exists(select 1 from public.arena_seasons s where s.id=p_season_id and (s.visibility='public' or s.created_by=v_uid or private.is_admin_user())) then raise exception 'season leaderboard unavailable'; end if;
  select p.university,p.region into v_university,v_region from public.profiles p where p.id=v_uid;
  v_start := case p_period when 'daily' then date_trunc('day',now()) when 'weekly' then date_trunc('week',now()) when 'monthly' then date_trunc('month',now()) else null end;
  return query
  with base as (
    select r.user_id,p.full_name,p.avatar_url,r.rating,r.xp,r.wins,r.matches_played,
      case when p_period='all_time' then r.xp else coalesce((select sum(h.xp_awarded)::bigint from public.arena_rating_history h where h.user_id=r.user_id and h.arena_type=p_arena_type and h.created_at>=v_start),0) end as period_xp
      from public.arena_player_ratings r join public.profiles p on p.id=r.user_id
     where r.arena_type=p_arena_type
       and (p_scope<>'university' or (v_university is not null and p.university=v_university))
       and (p_scope<>'region' or (v_region is not null and p.region=v_region))
       and (p_scope<>'career_path' or exists(select 1 from public.arena_rating_history h join public.arena_matches m on m.id=h.match_id where h.user_id=r.user_id and h.arena_type=p_arena_type and m.career_path_id=p_career_path_id))
       and (p_scope<>'season' or exists(select 1 from public.arena_rating_history h join public.arena_matches m on m.id=h.match_id where h.user_id=r.user_id and h.arena_type=p_arena_type and m.season_id=p_season_id))
  ), ranked as (
    select row_number() over(order by case when p_period='all_time' then b.rating::bigint else b.period_xp end desc,b.rating desc,b.xp desc,b.user_id) as leaderboard_rank,b.* from base b
  )
  select x.leaderboard_rank,x.user_id,x.full_name,x.avatar_url,x.rating,x.xp,x.wins,x.matches_played,x.period_xp
    from ranked x order by x.leaderboard_rank limit greatest(1,least(coalesce(p_limit,50),100));
end
$$;

revoke all on all functions in schema arena_read from public;
grant execute on function arena_read.get_live_state(uuid) to anon,authenticated,service_role;
grant execute on function arena_read.get_live_scoreboard(uuid) to anon,authenticated,service_role;
grant execute on function arena_read.get_leaderboard(text,text,text,uuid,uuid,integer) to anon,authenticated,service_role;

create or replace function public.get_arena_live_state(p_match_id uuid)
returns jsonb language sql security invoker set search_path=''
as $$ select arena_read.get_live_state(p_match_id); $$;

create or replace function public.get_arena_live_scoreboard(p_match_id uuid)
returns table(rank bigint,user_id uuid,full_name text,avatar_url text,team_name text,score integer,placement integer,status text)
language sql security invoker set search_path=''
as $$ select * from arena_read.get_live_scoreboard(p_match_id); $$;

create or replace function public.get_arena_leaderboard(p_scope text default 'global',p_period text default 'all_time',p_arena_type text default 'overall',p_career_path_id uuid default null,p_season_id uuid default null,p_limit integer default 50)
returns table(rank bigint,user_id uuid,full_name text,avatar_url text,rating integer,xp bigint,wins integer,matches_played integer,period_xp bigint)
language sql security invoker set search_path=''
as $$ select * from arena_read.get_leaderboard(p_scope,p_period,p_arena_type,p_career_path_id,p_season_id,p_limit); $$;

revoke all on function public.get_arena_live_state(uuid) from public;
revoke all on function public.get_arena_live_scoreboard(uuid) from public;
revoke all on function public.get_arena_leaderboard(text,text,text,uuid,uuid,integer) from public;
grant execute on function public.get_arena_live_state(uuid) to anon,authenticated,service_role;
grant execute on function public.get_arena_live_scoreboard(uuid) to anon,authenticated,service_role;
grant execute on function public.get_arena_leaderboard(text,text,text,uuid,uuid,integer) to anon,authenticated,service_role;
;
