-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812233648
create unique index if not exists arena_rewards_rule_user_uq on public.arena_rewards(rule_id,beneficiary_user_id) where beneficiary_user_id is not null;
create unique index if not exists arena_rewards_rule_arena_team_uq on public.arena_rewards(rule_id,beneficiary_arena_team_id) where beneficiary_arena_team_id is not null;
create unique index if not exists arena_rewards_rule_tournament_team_uq on public.arena_rewards(rule_id,beneficiary_tournament_team_id) where beneficiary_tournament_team_id is not null;

create or replace function private.create_arena_season(p_title text,p_slug text,p_description text default null,p_arena_type text default null,p_career_path_id uuid default null,p_visibility text default 'public',p_starts_at timestamptz default null,p_ends_at timestamptz default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=(select auth.uid()); v_id uuid;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if nullif(trim(p_title),'') is null or nullif(trim(p_slug),'') is null then raise exception 'title and slug required'; end if;
  if p_visibility not in ('public','private','invite') then raise exception 'invalid visibility'; end if;
  insert into public.arena_seasons(title,slug,description,arena_type,career_path_id,visibility,status,starts_at,ends_at,created_by)
  values(left(trim(p_title),160),lower(regexp_replace(trim(p_slug),'[^a-zA-Z0-9-]+','-','g')),left(p_description,4000),p_arena_type,p_career_path_id,p_visibility,'draft',p_starts_at,p_ends_at,v_uid) returning id into v_id;
  return v_id;
end $$;

create or replace function private.set_arena_season_status(p_season_id uuid,p_status text)
returns void language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=(select auth.uid());
begin
  if p_status not in ('draft','open','active','completed','cancelled') then raise exception 'invalid season status'; end if;
  if not exists(select 1 from public.arena_seasons s where s.id=p_season_id and (s.created_by=v_uid or private.is_admin_user())) then raise exception 'season creator access required'; end if;
  update public.arena_seasons set status=p_status,updated_at=now() where id=p_season_id;
end $$;

create or replace function private.create_arena_tournament(p_title text,p_arena_type text,p_format text default 'single_elimination',p_team_mode boolean default false,p_assessment_id uuid default null,p_career_path_id uuid default null,p_season_id uuid default null,p_visibility text default 'public',p_max_competitors integer default 16,p_registration_deadline timestamptz default null,p_starts_at timestamptz default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=(select auth.uid()); v_id uuid;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if p_arena_type not in ('quiz_battle','speed_quiz','interview_practice','case_sprint','team_battle','skill_sprint','employer_challenge') then raise exception 'invalid arena type'; end if;
  if p_format not in ('single_elimination','round_robin') then raise exception 'invalid tournament format'; end if;
  if p_visibility not in ('public','private','invite') then raise exception 'invalid visibility'; end if;
  if p_arena_type in ('quiz_battle','speed_quiz') and p_assessment_id is null then raise exception 'assessment required for quiz tournament'; end if;
  if p_assessment_id is not null and not exists(select 1 from public.skill_assessments where id=p_assessment_id and status='published') then raise exception 'published assessment not found'; end if;
  if p_season_id is not null and not exists(select 1 from public.arena_seasons s where s.id=p_season_id and (s.visibility='public' or s.created_by=v_uid or private.is_admin_user())) then raise exception 'season not found'; end if;
  insert into public.arena_tournaments(season_id,title,arena_type,format,visibility,status,team_mode,assessment_id,career_path_id,max_competitors,registration_deadline,starts_at,created_by)
  values(p_season_id,left(trim(p_title),180),p_arena_type,p_format,p_visibility,'draft',coalesce(p_team_mode,false),p_assessment_id,p_career_path_id,greatest(2,least(coalesce(p_max_competitors,16),128)),p_registration_deadline,p_starts_at,v_uid) returning id into v_id;
  return v_id;
end $$;

create or replace function private.open_arena_tournament_registration(p_tournament_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=(select auth.uid());
begin
  if not exists(select 1 from public.arena_tournaments t where t.id=p_tournament_id and t.status='draft' and (t.created_by=v_uid or private.is_admin_user())) then raise exception 'tournament creator access required'; end if;
  update public.arena_tournaments set status='registration',updated_at=now() where id=p_tournament_id;
end $$;

create or replace function private.register_arena_tournament(p_tournament_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=(select auth.uid()); v_t public.arena_tournaments; v_id uuid; v_count integer;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select * into v_t from public.arena_tournaments where id=p_tournament_id for update;
  if v_t.id is null or v_t.status<>'registration' or v_t.team_mode then raise exception 'individual registration unavailable'; end if;
  if v_t.registration_deadline is not null and now()>v_t.registration_deadline then raise exception 'registration closed'; end if;
  select count(*) into v_count from public.arena_tournament_competitors where tournament_id=p_tournament_id and status<>'withdrawn';
  if v_count>=v_t.max_competitors then raise exception 'tournament is full'; end if;
  insert into public.arena_tournament_competitors(tournament_id,user_id,status) values(p_tournament_id,v_uid,'registered') on conflict do nothing returning id into v_id;
  if v_id is null then select id into v_id from public.arena_tournament_competitors where tournament_id=p_tournament_id and user_id=v_uid; end if;
  return v_id;
end $$;

create or replace function private.create_arena_tournament_team(p_tournament_id uuid,p_name text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=(select auth.uid()); v_t public.arena_tournaments; v_id uuid; v_code text;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select * into v_t from public.arena_tournaments where id=p_tournament_id;
  if v_t.id is null or v_t.status<>'registration' or not v_t.team_mode then raise exception 'team registration unavailable'; end if;
  v_code:=upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));
  insert into public.arena_tournament_teams(tournament_id,name,captain_id,join_code) values(p_tournament_id,left(trim(p_name),100),v_uid,v_code) returning id into v_id;
  insert into public.arena_tournament_team_members(team_id,user_id) values(v_id,v_uid);
  return jsonb_build_object('team_id',v_id,'join_code',v_code);
end $$;

create or replace function private.join_arena_tournament_team(p_join_code text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=(select auth.uid()); v_team public.arena_tournament_teams; v_t public.arena_tournaments;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select * into v_team from public.arena_tournament_teams where join_code=upper(trim(p_join_code)) and status='active';
  if v_team.id is null then raise exception 'team not found'; end if;
  select * into v_t from public.arena_tournaments where id=v_team.tournament_id;
  if v_t.status<>'registration' then raise exception 'registration closed'; end if;
  if exists(select 1 from public.arena_tournament_team_members tm join public.arena_tournament_teams t on t.id=tm.team_id where t.tournament_id=v_t.id and tm.user_id=v_uid) then raise exception 'already on a tournament team'; end if;
  insert into public.arena_tournament_team_members(team_id,user_id) values(v_team.id,v_uid);
  return v_team.id;
end $$;

create or replace function private.register_arena_tournament_team(p_team_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=(select auth.uid()); v_team public.arena_tournament_teams; v_t public.arena_tournaments; v_count integer; v_id uuid;
begin
  select * into v_team from public.arena_tournament_teams where id=p_team_id and captain_id=v_uid and status='active';
  if v_team.id is null then raise exception 'team captain access required'; end if;
  select * into v_t from public.arena_tournaments where id=v_team.tournament_id for update;
  if v_t.status<>'registration' or not v_t.team_mode then raise exception 'team registration unavailable'; end if;
  select count(*) into v_count from public.arena_tournament_competitors where tournament_id=v_t.id and status<>'withdrawn';
  if v_count>=v_t.max_competitors then raise exception 'tournament is full'; end if;
  insert into public.arena_tournament_competitors(tournament_id,tournament_team_id,status) values(v_t.id,p_team_id,'registered') on conflict do nothing returning id into v_id;
  if v_id is null then select id into v_id from public.arena_tournament_competitors where tournament_id=v_t.id and tournament_team_id=p_team_id; end if;
  return v_id;
end $$;

create or replace function private.create_tournament_pairing_match(p_pairing_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_p public.arena_tournament_pairings; v_r public.arena_tournament_rounds; v_t public.arena_tournaments; v_a public.arena_tournament_competitors; v_b public.arena_tournament_competitors; v_match uuid; v_min integer; v_max integer; v_at_a uuid; v_at_b uuid; v_round_type text; v_prompt text;
begin
  select * into v_p from public.arena_tournament_pairings where id=p_pairing_id for update;
  if v_p.id is null or v_p.competitor_b_id is null then return null; end if;
  if v_p.arena_match_id is not null then return v_p.arena_match_id; end if;
  select * into v_r from public.arena_tournament_rounds where id=v_p.tournament_round_id;
  select * into v_t from public.arena_tournaments where id=v_r.tournament_id;
  select * into v_a from public.arena_tournament_competitors where id=v_p.competitor_a_id;
  select * into v_b from public.arena_tournament_competitors where id=v_p.competitor_b_id;
  if v_t.team_mode then
    select count(*) into v_min from public.arena_tournament_team_members where team_id in (v_a.tournament_team_id,v_b.tournament_team_id);
    v_max:=greatest(2,least(v_min,100));
  else v_min:=2; v_max:=2; end if;
  insert into public.arena_matches(title,description,arena_type,creator_id,visibility,assessment_id,career_path_id,season_id,tournament_id,tournament_pairing_id,min_participants,max_participants,team_mode,status,scoring_mode,rated,integrity_required,rules)
  values(v_t.title||' — Round '||v_r.round_no,'Tournament match',v_t.arena_type,v_t.created_by,v_t.visibility,v_t.assessment_id,v_t.career_path_id,v_t.season_id,v_t.id,v_p.id,v_min,v_max,v_t.team_mode,'open',case when v_t.arena_type in ('quiz_battle','speed_quiz') then 'auto' else 'judge' end,true,v_t.arena_type in ('quiz_battle','speed_quiz','employer_challenge'),jsonb_build_object('tournament',true,'round_no',v_r.round_no)) returning id into v_match;
  if not v_t.team_mode then
    insert into public.arena_participants(match_id,user_id,status,ready) values(v_match,v_a.user_id,'joined',false),(v_match,v_b.user_id,'joined',false);
  else
    insert into public.arena_teams(match_id,name,captain_id,tournament_team_id,join_code)
    select v_match,t.name,t.captain_id,t.id,upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)) from public.arena_tournament_teams t where t.id=v_a.tournament_team_id returning id into v_at_a;
    insert into public.arena_teams(match_id,name,captain_id,tournament_team_id,join_code)
    select v_match,t.name,t.captain_id,t.id,upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)) from public.arena_tournament_teams t where t.id=v_b.tournament_team_id returning id into v_at_b;
    insert into public.arena_team_members(team_id,user_id) select v_at_a,user_id from public.arena_tournament_team_members where team_id=v_a.tournament_team_id;
    insert into public.arena_team_members(team_id,user_id) select v_at_b,user_id from public.arena_tournament_team_members where team_id=v_b.tournament_team_id;
    insert into public.arena_participants(match_id,user_id,status,ready,team_id) select v_match,user_id,'joined',false,v_at_a from public.arena_tournament_team_members where team_id=v_a.tournament_team_id;
    insert into public.arena_participants(match_id,user_id,status,ready,team_id) select v_match,user_id,'joined',false,v_at_b from public.arena_tournament_team_members where team_id=v_b.tournament_team_id;
  end if;
  if v_t.arena_type not in ('quiz_battle','speed_quiz') then
    v_round_type:=case v_t.arena_type when 'interview_practice' then 'interview' when 'case_sprint' then 'case' when 'employer_challenge' then 'presentation' else 'task' end;
    v_prompt:=case v_t.arena_type when 'interview_practice' then 'Complete the tournament interview round.' when 'case_sprint' then 'Analyze the tournament case and submit your recommendation.' when 'employer_challenge' then 'Present your employer challenge solution.' else 'Complete the tournament skill task.' end;
    insert into public.arena_rounds(match_id,round_order,round_type,title,prompt,max_points,time_limit_seconds,state) values(v_match,1,v_round_type,'Tournament Round',v_prompt,100,1200,'planned');
  end if;
  update public.arena_tournament_pairings set arena_match_id=v_match,status='pending' where id=p_pairing_id;
  return v_match;
end $$;

create or replace function private.start_arena_tournament(p_tournament_id uuid)
returns integer language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=(select auth.uid()); v_t public.arena_tournaments; v_n integer; v_round uuid; a record; b record; v_pair uuid; v_created integer:=0; arr uuid[]; i integer;
begin
  select * into v_t from public.arena_tournaments where id=p_tournament_id for update;
  if v_t.id is null or v_t.status<>'registration' or (v_t.created_by<>v_uid and not private.is_admin_user()) then raise exception 'tournament creator access required'; end if;
  select count(*) into v_n from public.arena_tournament_competitors where tournament_id=p_tournament_id and status='registered';
  if v_n<2 then raise exception 'at least two competitors required'; end if;
  with s as (select id,row_number() over(order by created_at,id) seed from public.arena_tournament_competitors where tournament_id=p_tournament_id and status='registered') update public.arena_tournament_competitors c set seed=s.seed,status='active' from s where c.id=s.id;
  update public.arena_tournaments set status='in_progress',starts_at=coalesce(starts_at,now()),updated_at=now() where id=p_tournament_id;
  insert into public.arena_tournament_rounds(tournament_id,round_no,title,status,starts_at) values(p_tournament_id,1,case when v_t.format='round_robin' then 'Round Robin' else 'Round 1' end,'active',now()) returning id into v_round;
  if v_t.format='round_robin' then
    for a in select id from public.arena_tournament_competitors where tournament_id=p_tournament_id and status='active' order by seed loop
      for b in select id from public.arena_tournament_competitors where tournament_id=p_tournament_id and status='active' and seed>(select seed from public.arena_tournament_competitors where id=a.id) order by seed loop
        insert into public.arena_tournament_pairings(tournament_round_id,competitor_a_id,competitor_b_id,status) values(v_round,a.id,b.id,'pending') returning id into v_pair;
        perform private.create_tournament_pairing_match(v_pair); v_created:=v_created+1;
      end loop;
    end loop;
  else
    select array_agg(id order by seed) into arr from public.arena_tournament_competitors where tournament_id=p_tournament_id and status='active';
    i:=1;
    while i<=array_length(arr,1) loop
      if i=array_length(arr,1) then
        insert into public.arena_tournament_pairings(tournament_round_id,competitor_a_id,competitor_b_id,winner_competitor_id,status,completed_at) values(v_round,arr[i],null,arr[i],'bye',now());
      else
        insert into public.arena_tournament_pairings(tournament_round_id,competitor_a_id,competitor_b_id,status) values(v_round,arr[i],arr[i+1],'pending') returning id into v_pair;
        perform private.create_tournament_pairing_match(v_pair); v_created:=v_created+1;
      end if;
      i:=i+2;
    end loop;
  end if;
  return v_created;
end $$;

create or replace function private.add_arena_reward_rule(p_match_id uuid default null,p_tournament_id uuid default null,p_placement integer default 1,p_reward_type text default 'achievement',p_coin_amount integer default null,p_cash_amount numeric default null,p_currency text default 'ETB',p_badge_id uuid default null,p_achievement_title text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=(select auth.uid()); v_id uuid;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if ((p_match_id is not null)::int+(p_tournament_id is not null)::int)<>1 then raise exception 'exactly one reward source required'; end if;
  if p_reward_type not in ('coins','badge','cash','achievement') then raise exception 'invalid reward type'; end if;
  if p_reward_type='coins' and coalesce(p_coin_amount,0)<=0 then raise exception 'coin amount required'; end if;
  if p_reward_type='cash' and coalesce(p_cash_amount,0)<=0 then raise exception 'cash amount required'; end if;
  if p_reward_type='badge' and (p_badge_id is null or not exists(select 1 from public.badges where id=p_badge_id)) then raise exception 'badge required'; end if;
  if p_reward_type='achievement' and nullif(trim(p_achievement_title),'') is null then raise exception 'achievement title required'; end if;
  if p_match_id is not null and not exists(select 1 from public.arena_matches m where m.id=p_match_id and (m.creator_id=v_uid or private.is_admin_user())) then raise exception 'arena creator access required'; end if;
  if p_tournament_id is not null and not exists(select 1 from public.arena_tournaments t where t.id=p_tournament_id and (t.created_by=v_uid or private.is_admin_user())) then raise exception 'tournament creator access required'; end if;
  insert into public.arena_reward_rules(match_id,tournament_id,placement,reward_type,coin_amount,cash_amount,currency,badge_id,achievement_title,created_by)
  values(p_match_id,p_tournament_id,greatest(1,p_placement),p_reward_type,p_coin_amount,p_cash_amount,upper(coalesce(p_currency,'ETB')),p_badge_id,left(p_achievement_title,180),v_uid) returning id into v_id;
  return v_id;
end $$;

create or replace function private.apply_arena_user_reward(p_rule public.arena_reward_rules,p_user_id uuid,p_match_id uuid default null,p_tournament_id uuid default null,p_placement integer default null,p_score numeric default null)
returns void language plpgsql security definer set search_path='' as $$
declare v_reward uuid; v_creator uuid;
begin
  if exists(select 1 from public.arena_rewards where rule_id=p_rule.id and beneficiary_user_id=p_user_id) then return; end if;
  insert into public.arena_rewards(rule_id,match_id,tournament_id,beneficiary_user_id,reward_type,coin_amount,cash_amount,currency,badge_id,achievement_title,status,available_at)
  values(p_rule.id,p_match_id,p_tournament_id,p_user_id,p_rule.reward_type,p_rule.coin_amount,p_rule.cash_amount,p_rule.currency,p_rule.badge_id,p_rule.achievement_title,case when p_rule.reward_type='cash' then 'pending' else 'paid' end,case when p_rule.reward_type='cash' then null else now() end) returning id into v_reward;
  if p_rule.reward_type='coins' then update public.profiles set coin_balance=coin_balance+coalesce(p_rule.coin_amount,0),updated_at=now() where id=p_user_id;
  elsif p_rule.reward_type='badge' then insert into public.user_badges(user_id,badge_id) values(p_user_id,p_rule.badge_id) on conflict do nothing;
  elsif p_rule.reward_type='achievement' then
    select coalesce((select creator_id from public.arena_matches where id=p_match_id),(select created_by from public.arena_tournaments where id=p_tournament_id)) into v_creator;
    insert into public.career_passport_achievements(user_id,achievement_type,title,issuer,description,source_table,source_id,placement,score,verified,verified_by,verified_at,metadata)
    values(p_user_id,'arena',p_rule.achievement_title,'Mela Arena','Verified competitive Arena achievement.',case when p_match_id is not null then 'arena_matches' else 'arena_tournaments' end,coalesce(p_match_id,p_tournament_id),p_placement,p_score,true,v_creator,now(),jsonb_build_object('reward_rule_id',p_rule.id)) on conflict do nothing;
  end if;
  insert into public.notifications(user_id,title,body,ref_table,ref_id) values(p_user_id,'Arena reward earned',case when p_rule.reward_type='cash' then 'You earned an Arena cash reward. Payment remains pending until settlement is confirmed.' else 'You earned an Arena reward.' end,'arena_rewards',v_reward);
end $$;

create or replace function private.process_arena_match_rewards(p_match_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare v_m public.arena_matches; r public.arena_reward_rules; p record; v_team uuid;
begin
  select * into v_m from public.arena_matches where id=p_match_id for update;
  if v_m.id is null or v_m.status<>'completed' or v_m.reward_processed_at is not null then return; end if;
  for r in select * from public.arena_reward_rules where match_id=p_match_id and active=true order by placement loop
    if v_m.team_mode and r.reward_type='cash' then
      select team_id into v_team from public.arena_participants where match_id=p_match_id and placement=r.placement and team_id is not null order by team_id limit 1;
      if v_team is not null and not exists(select 1 from public.arena_rewards where rule_id=r.id and beneficiary_arena_team_id=v_team) then
        insert into public.arena_rewards(rule_id,match_id,beneficiary_arena_team_id,reward_type,cash_amount,currency,status) values(r.id,p_match_id,v_team,'cash',r.cash_amount,r.currency,'pending');
      end if;
    else
      for p in select user_id,placement,score from public.arena_participants where match_id=p_match_id and placement=r.placement and integrity_status<>'disqualified' loop perform private.apply_arena_user_reward(r,p.user_id,p_match_id,null,p.placement,p.score); end loop;
    end if;
  end loop;
  update public.arena_matches set reward_processed_at=now(),updated_at=now() where id=p_match_id;
end $$;

create or replace function private.process_arena_tournament_rewards(p_tournament_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare v_t public.arena_tournaments; r public.arena_reward_rules; c record; u record;
begin
  select * into v_t from public.arena_tournaments where id=p_tournament_id;
  if v_t.id is null or v_t.status<>'completed' then return; end if;
  for r in select * from public.arena_reward_rules where tournament_id=p_tournament_id and active=true loop
    for c in select * from public.arena_tournament_competitors where tournament_id=p_tournament_id and placement=r.placement loop
      if c.user_id is not null then perform private.apply_arena_user_reward(r,c.user_id,null,p_tournament_id,c.placement,c.points);
      elsif r.reward_type='cash' then
        if not exists(select 1 from public.arena_rewards where rule_id=r.id and beneficiary_tournament_team_id=c.tournament_team_id) then insert into public.arena_rewards(rule_id,tournament_id,beneficiary_tournament_team_id,reward_type,cash_amount,currency,status) values(r.id,p_tournament_id,c.tournament_team_id,'cash',r.cash_amount,r.currency,'pending'); end if;
      else
        for u in select user_id from public.arena_tournament_team_members where team_id=c.tournament_team_id loop perform private.apply_arena_user_reward(r,u.user_id,null,p_tournament_id,c.placement,c.points); end loop;
      end if;
    end loop;
  end loop;
end $$;

create or replace function private.advance_arena_tournament(p_tournament_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare v_t public.arena_tournaments; v_round public.arena_tournament_rounds; v_pending integer; v_winners uuid[]; v_n integer; v_new_round uuid; v_pair uuid; i integer; v_pair_count integer;
begin
  select * into v_t from public.arena_tournaments where id=p_tournament_id for update;
  if v_t.id is null or v_t.status<>'in_progress' then return; end if;
  select * into v_round from public.arena_tournament_rounds where tournament_id=p_tournament_id and status='active' order by round_no desc limit 1;
  if v_round.id is null then return; end if;
  select count(*) into v_pending from public.arena_tournament_pairings where tournament_round_id=v_round.id and status not in ('completed','bye','cancelled');
  if v_pending>0 then return; end if;
  update public.arena_tournament_rounds set status='completed',completed_at=now() where id=v_round.id;
  if v_t.format='round_robin' then
    with ranked as (select id,row_number() over(order by points desc,seed asc) rn from public.arena_tournament_competitors where tournament_id=p_tournament_id and status<>'withdrawn') update public.arena_tournament_competitors c set placement=r.rn,status=case when r.rn=1 then 'winner' else 'eliminated' end from ranked r where c.id=r.id;
    update public.arena_tournaments set status='completed',ends_at=now(),updated_at=now() where id=p_tournament_id;
    perform private.process_arena_tournament_rewards(p_tournament_id); return;
  end if;
  select array_agg(winner_competitor_id order by created_at) into v_winners from public.arena_tournament_pairings where tournament_round_id=v_round.id and winner_competitor_id is not null;
  v_n:=coalesce(array_length(v_winners,1),0);
  if v_n=1 then
    update public.arena_tournament_competitors set placement=1,status='winner' where id=v_winners[1];
    update public.arena_tournament_teams tt set status='winner' where exists(select 1 from public.arena_tournament_competitors c where c.id=v_winners[1] and c.tournament_team_id=tt.id);
    update public.arena_tournaments set status='completed',ends_at=now(),updated_at=now() where id=p_tournament_id;
    perform private.process_arena_tournament_rewards(p_tournament_id); return;
  end if;
  insert into public.arena_tournament_rounds(tournament_id,round_no,title,status,starts_at) values(p_tournament_id,v_round.round_no+1,'Round '||(v_round.round_no+1),'active',now()) returning id into v_new_round;
  i:=1;
  while i<=v_n loop
    if i=v_n then insert into public.arena_tournament_pairings(tournament_round_id,competitor_a_id,competitor_b_id,winner_competitor_id,status,completed_at) values(v_new_round,v_winners[i],null,v_winners[i],'bye',now());
    else insert into public.arena_tournament_pairings(tournament_round_id,competitor_a_id,competitor_b_id,status) values(v_new_round,v_winners[i],v_winners[i+1],'pending') returning id into v_pair; perform private.create_tournament_pairing_match(v_pair); end if;
    i:=i+2;
  end loop;
end $$;

create or replace function private.sync_arena_tournament_pairing(p_match_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare v_m public.arena_matches; v_p public.arena_tournament_pairings; v_r public.arena_tournament_rounds; v_t public.arena_tournaments; v_winner uuid; v_loser uuid; v_pair_count integer; v_win_user uuid; v_win_tteam uuid;
begin
  select * into v_m from public.arena_matches where id=p_match_id;
  if v_m.id is null or v_m.tournament_pairing_id is null or v_m.status<>'completed' then return; end if;
  select * into v_p from public.arena_tournament_pairings where id=v_m.tournament_pairing_id for update;
  if v_p.status='completed' then return; end if;
  select * into v_r from public.arena_tournament_rounds where id=v_p.tournament_round_id;
  select * into v_t from public.arena_tournaments where id=v_r.tournament_id;
  if v_t.team_mode then
    select at.tournament_team_id into v_win_tteam from public.arena_participants ap join public.arena_teams at on at.id=ap.team_id where ap.match_id=p_match_id and ap.placement=1 order by ap.user_id limit 1;
    select id into v_winner from public.arena_tournament_competitors where tournament_id=v_t.id and tournament_team_id=v_win_tteam;
  else
    select user_id into v_win_user from public.arena_participants where match_id=p_match_id and placement=1 order by user_id limit 1;
    select id into v_winner from public.arena_tournament_competitors where tournament_id=v_t.id and user_id=v_win_user;
  end if;
  if v_winner is null then return; end if;
  v_loser:=case when v_p.competitor_a_id=v_winner then v_p.competitor_b_id else v_p.competitor_a_id end;
  update public.arena_tournament_pairings set winner_competitor_id=v_winner,status='completed',completed_at=now() where id=v_p.id;
  update public.arena_tournament_competitors set points=points+3 where id=v_winner;
  if v_t.format='single_elimination' and v_loser is not null then
    select count(*) into v_pair_count from public.arena_tournament_pairings where tournament_round_id=v_r.id and competitor_b_id is not null;
    update public.arena_tournament_competitors set status='eliminated',placement=case when v_pair_count=1 then 2 when v_pair_count=2 then 3 else placement end where id=v_loser;
    update public.arena_tournament_teams tt set status='eliminated' where exists(select 1 from public.arena_tournament_competitors c where c.id=v_loser and c.tournament_team_id=tt.id);
  end if;
  perform private.advance_arena_tournament(v_t.id);
end $$;

create or replace function private.arena_match_completed_pipeline()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.status='completed' and old.status is distinct from 'completed' then
    perform private.process_arena_ratings(new.id);
    perform private.process_arena_match_rewards(new.id);
    if new.tournament_pairing_id is not null then perform private.sync_arena_tournament_pairing(new.id); end if;
  end if;
  return new;
end $$;
drop trigger if exists arena_match_completed_pipeline on public.arena_matches;
create trigger arena_match_completed_pipeline after update of status on public.arena_matches for each row execute function private.arena_match_completed_pipeline();

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
end $$;

create or replace function private.record_arena_cash_reward_paid(p_reward_id uuid,p_external_ref text)
returns void language plpgsql security definer set search_path='' as $$
begin
  if p_external_ref is null or length(trim(p_external_ref))<3 then raise exception 'external settlement reference required'; end if;
  update public.arena_rewards set status='paid',external_ref=left(trim(p_external_ref),200),paid_at=now(),available_at=coalesce(available_at,now()) where id=p_reward_id and reward_type='cash' and status in ('pending','available');
  if not found then raise exception 'pending cash reward not found'; end if;
end $$;

create or replace function public.create_arena_season(p_title text,p_slug text,p_description text default null,p_arena_type text default null,p_career_path_id uuid default null,p_visibility text default 'public',p_starts_at timestamptz default null,p_ends_at timestamptz default null) returns uuid language sql security invoker set search_path='' as $$ select private.create_arena_season(p_title,p_slug,p_description,p_arena_type,p_career_path_id,p_visibility,p_starts_at,p_ends_at); $$;
create or replace function public.set_arena_season_status(p_season_id uuid,p_status text) returns void language sql security invoker set search_path='' as $$ select private.set_arena_season_status(p_season_id,p_status); $$;
create or replace function public.create_arena_tournament(p_title text,p_arena_type text,p_format text default 'single_elimination',p_team_mode boolean default false,p_assessment_id uuid default null,p_career_path_id uuid default null,p_season_id uuid default null,p_visibility text default 'public',p_max_competitors integer default 16,p_registration_deadline timestamptz default null,p_starts_at timestamptz default null) returns uuid language sql security invoker set search_path='' as $$ select private.create_arena_tournament(p_title,p_arena_type,p_format,p_team_mode,p_assessment_id,p_career_path_id,p_season_id,p_visibility,p_max_competitors,p_registration_deadline,p_starts_at); $$;
create or replace function public.open_arena_tournament_registration(p_tournament_id uuid) returns void language sql security invoker set search_path='' as $$ select private.open_arena_tournament_registration(p_tournament_id); $$;
create or replace function public.register_arena_tournament(p_tournament_id uuid) returns uuid language sql security invoker set search_path='' as $$ select private.register_arena_tournament(p_tournament_id); $$;
create or replace function public.create_arena_tournament_team(p_tournament_id uuid,p_name text) returns jsonb language sql security invoker set search_path='' as $$ select private.create_arena_tournament_team(p_tournament_id,p_name); $$;
create or replace function public.join_arena_tournament_team(p_join_code text) returns uuid language sql security invoker set search_path='' as $$ select private.join_arena_tournament_team(p_join_code); $$;
create or replace function public.register_arena_tournament_team(p_team_id uuid) returns uuid language sql security invoker set search_path='' as $$ select private.register_arena_tournament_team(p_team_id); $$;
create or replace function public.start_arena_tournament(p_tournament_id uuid) returns integer language sql security invoker set search_path='' as $$ select private.start_arena_tournament(p_tournament_id); $$;
create or replace function public.add_arena_reward_rule(p_match_id uuid default null,p_tournament_id uuid default null,p_placement integer default 1,p_reward_type text default 'achievement',p_coin_amount integer default null,p_cash_amount numeric default null,p_currency text default 'ETB',p_badge_id uuid default null,p_achievement_title text default null) returns uuid language sql security invoker set search_path='' as $$ select private.add_arena_reward_rule(p_match_id,p_tournament_id,p_placement,p_reward_type,p_coin_amount,p_cash_amount,p_currency,p_badge_id,p_achievement_title); $$;

revoke execute on function private.create_arena_season(text,text,text,text,uuid,text,timestamptz,timestamptz),private.set_arena_season_status(uuid,text),private.create_arena_tournament(text,text,text,boolean,uuid,uuid,uuid,text,integer,timestamptz,timestamptz),private.open_arena_tournament_registration(uuid),private.register_arena_tournament(uuid),private.create_arena_tournament_team(uuid,text),private.join_arena_tournament_team(text),private.register_arena_tournament_team(uuid),private.start_arena_tournament(uuid),private.add_arena_reward_rule(uuid,uuid,integer,text,integer,numeric,text,uuid,text) from public,anon;
grant execute on function private.create_arena_season(text,text,text,text,uuid,text,timestamptz,timestamptz),private.set_arena_season_status(uuid,text),private.create_arena_tournament(text,text,text,boolean,uuid,uuid,uuid,text,integer,timestamptz,timestamptz),private.open_arena_tournament_registration(uuid),private.register_arena_tournament(uuid),private.create_arena_tournament_team(uuid,text),private.join_arena_tournament_team(text),private.register_arena_tournament_team(uuid),private.start_arena_tournament(uuid),private.add_arena_reward_rule(uuid,uuid,integer,text,integer,numeric,text,uuid,text) to authenticated;
revoke execute on function private.create_tournament_pairing_match(uuid),private.apply_arena_user_reward(public.arena_reward_rules,uuid,uuid,uuid,integer,numeric),private.process_arena_match_rewards(uuid),private.process_arena_tournament_rewards(uuid),private.advance_arena_tournament(uuid),private.sync_arena_tournament_pairing(uuid),private.arena_match_completed_pipeline(),private.record_arena_cash_reward_paid(uuid,text) from public,anon,authenticated;
grant execute on function private.record_arena_cash_reward_paid(uuid,text) to service_role;
revoke execute on function public.create_arena_season(text,text,text,text,uuid,text,timestamptz,timestamptz),public.set_arena_season_status(uuid,text),public.create_arena_tournament(text,text,text,boolean,uuid,uuid,uuid,text,integer,timestamptz,timestamptz),public.open_arena_tournament_registration(uuid),public.register_arena_tournament(uuid),public.create_arena_tournament_team(uuid,text),public.join_arena_tournament_team(text),public.register_arena_tournament_team(uuid),public.start_arena_tournament(uuid),public.add_arena_reward_rule(uuid,uuid,integer,text,integer,numeric,text,uuid,text) from public,anon;
grant execute on function public.create_arena_season(text,text,text,text,uuid,text,timestamptz,timestamptz),public.set_arena_season_status(uuid,text),public.create_arena_tournament(text,text,text,boolean,uuid,uuid,uuid,text,integer,timestamptz,timestamptz),public.open_arena_tournament_registration(uuid),public.register_arena_tournament(uuid),public.create_arena_tournament_team(uuid,text),public.join_arena_tournament_team(text),public.register_arena_tournament_team(uuid),public.start_arena_tournament(uuid),public.add_arena_reward_rule(uuid,uuid,integer,text,integer,numeric,text,uuid,text) to authenticated;
;
