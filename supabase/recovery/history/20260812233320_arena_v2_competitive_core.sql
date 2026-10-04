-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812233320
create table if not exists public.arena_seasons (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  slug text not null unique,
  description text,
  arena_type text,
  career_path_id uuid references public.career_paths(id) on delete set null,
  visibility text not null default 'public' check (visibility in ('public','private','invite')),
  status text not null default 'draft' check (status in ('draft','open','active','completed','cancelled')),
  starts_at timestamptz,
  ends_at timestamptz,
  rules jsonb not null default '{}'::jsonb,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (arena_type is null or arena_type in ('quiz_battle','speed_quiz','interview_practice','case_sprint','team_battle','skill_sprint','employer_challenge')),
  check (ends_at is null or starts_at is null or ends_at > starts_at)
);

create table if not exists public.arena_tournaments (
  id uuid primary key default gen_random_uuid(),
  season_id uuid references public.arena_seasons(id) on delete set null,
  title text not null,
  description text,
  arena_type text not null check (arena_type in ('quiz_battle','speed_quiz','interview_practice','case_sprint','team_battle','skill_sprint','employer_challenge')),
  format text not null default 'single_elimination' check (format in ('single_elimination','round_robin')),
  visibility text not null default 'public' check (visibility in ('public','private','invite')),
  status text not null default 'draft' check (status in ('draft','registration','in_progress','completed','cancelled')),
  team_mode boolean not null default false,
  assessment_id uuid references public.skill_assessments(id) on delete set null,
  career_path_id uuid references public.career_paths(id) on delete set null,
  max_competitors integer not null default 16 check (max_competitors between 2 and 128),
  registration_deadline timestamptz,
  starts_at timestamptz,
  ends_at timestamptz,
  rules jsonb not null default '{}'::jsonb,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (arena_type not in ('quiz_battle','speed_quiz') or assessment_id is not null)
);

create table if not exists public.arena_tournament_teams (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.arena_tournaments(id) on delete cascade,
  name text not null,
  captain_id uuid not null references public.profiles(id) on delete cascade,
  join_code text not null unique,
  status text not null default 'active' check (status in ('active','withdrawn','eliminated','winner')),
  created_at timestamptz not null default now(),
  unique(tournament_id,name)
);

create table if not exists public.arena_tournament_team_members (
  team_id uuid not null references public.arena_tournament_teams(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key(team_id,user_id)
);

create table if not exists public.arena_tournament_competitors (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.arena_tournaments(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete cascade,
  tournament_team_id uuid references public.arena_tournament_teams(id) on delete cascade,
  seed integer,
  status text not null default 'registered' check (status in ('registered','active','eliminated','winner','withdrawn')),
  placement integer,
  points numeric not null default 0,
  created_at timestamptz not null default now(),
  check (((user_id is not null)::int + (tournament_team_id is not null)::int) = 1)
);
create unique index if not exists arena_tournament_competitor_user_uq on public.arena_tournament_competitors(tournament_id,user_id) where user_id is not null;
create unique index if not exists arena_tournament_competitor_team_uq on public.arena_tournament_competitors(tournament_id,tournament_team_id) where tournament_team_id is not null;

create table if not exists public.arena_tournament_rounds (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.arena_tournaments(id) on delete cascade,
  round_no integer not null check (round_no >= 1),
  title text not null,
  status text not null default 'pending' check (status in ('pending','active','completed')),
  starts_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  unique(tournament_id,round_no)
);

create table if not exists public.arena_tournament_pairings (
  id uuid primary key default gen_random_uuid(),
  tournament_round_id uuid not null references public.arena_tournament_rounds(id) on delete cascade,
  competitor_a_id uuid not null references public.arena_tournament_competitors(id) on delete cascade,
  competitor_b_id uuid references public.arena_tournament_competitors(id) on delete cascade,
  arena_match_id uuid references public.arena_matches(id) on delete set null,
  winner_competitor_id uuid references public.arena_tournament_competitors(id) on delete set null,
  status text not null default 'pending' check (status in ('pending','live','completed','bye','cancelled')),
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  check (competitor_b_id is null or competitor_b_id <> competitor_a_id)
);

alter table public.arena_matches add column if not exists season_id uuid references public.arena_seasons(id) on delete set null;
alter table public.arena_matches add column if not exists tournament_id uuid references public.arena_tournaments(id) on delete set null;
alter table public.arena_matches add column if not exists tournament_pairing_id uuid references public.arena_tournament_pairings(id) on delete set null;
alter table public.arena_matches add column if not exists current_round_order integer;
alter table public.arena_matches add column if not exists round_started_at timestamptz;
alter table public.arena_matches add column if not exists round_ends_at timestamptz;
alter table public.arena_matches add column if not exists integrity_required boolean not null default false;
alter table public.arena_matches add column if not exists rated boolean not null default true;
alter table public.arena_matches add column if not exists rating_processed_at timestamptz;
alter table public.arena_matches add column if not exists reward_processed_at timestamptz;

alter table public.arena_participants add column if not exists rating_before integer;
alter table public.arena_participants add column if not exists rating_after integer;
alter table public.arena_participants add column if not exists rating_delta integer;
alter table public.arena_participants add column if not exists xp_awarded integer not null default 0;
alter table public.arena_participants add column if not exists result text check (result is null or result in ('win','loss','draw','placement'));
alter table public.arena_participants add column if not exists integrity_score numeric not null default 100 check (integrity_score between 0 and 100);
alter table public.arena_participants add column if not exists integrity_status text not null default 'clear' check (integrity_status in ('clear','review','flagged','disqualified'));

alter table public.arena_rounds add column if not exists state text not null default 'planned' check (state in ('planned','open','closed','scored'));
alter table public.arena_rounds add column if not exists opened_at timestamptz;
alter table public.arena_rounds add column if not exists closed_at timestamptz;

create table if not exists public.arena_player_ratings (
  user_id uuid not null references public.profiles(id) on delete cascade,
  arena_type text not null default 'overall',
  rating integer not null default 1000 check (rating between 100 and 5000),
  xp bigint not null default 0 check (xp >= 0),
  level integer not null default 1 check (level >= 1),
  matches_played integer not null default 0 check (matches_played >= 0),
  wins integer not null default 0 check (wins >= 0),
  losses integer not null default 0 check (losses >= 0),
  draws integer not null default 0 check (draws >= 0),
  current_streak integer not null default 0,
  best_streak integer not null default 0,
  last_match_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key(user_id,arena_type),
  check (arena_type in ('overall','quiz_battle','speed_quiz','interview_practice','case_sprint','team_battle','skill_sprint','employer_challenge'))
);

create table if not exists public.arena_rating_history (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.arena_matches(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  arena_type text not null,
  rating_before integer not null,
  rating_after integer not null,
  rating_delta integer not null,
  xp_awarded integer not null default 0,
  placement integer,
  result text not null check (result in ('win','loss','draw','placement')),
  created_at timestamptz not null default now(),
  unique(match_id,user_id,arena_type)
);

create table if not exists public.arena_matchmaking_queue (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  arena_type text not null check (arena_type in ('quiz_battle','speed_quiz','interview_practice','case_sprint','skill_sprint')),
  assessment_id uuid references public.skill_assessments(id) on delete set null,
  career_path_id uuid references public.career_paths(id) on delete set null,
  rating_snapshot integer not null default 1000,
  rating_range integer not null default 200 check (rating_range between 50 and 1000),
  status text not null default 'waiting' check (status in ('waiting','matched','cancelled','expired')),
  matched_match_id uuid references public.arena_matches(id) on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '30 minutes'),
  check (arena_type not in ('quiz_battle','speed_quiz') or assessment_id is not null)
);
create unique index if not exists arena_matchmaking_one_waiting_per_user on public.arena_matchmaking_queue(user_id) where status='waiting';

create table if not exists public.arena_judges (
  match_id uuid not null references public.arena_matches(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  assigned_by uuid not null references public.profiles(id) on delete cascade,
  judge_role text not null default 'judge' check (judge_role in ('judge','lead_judge')),
  status text not null default 'active' check (status in ('active','removed')),
  assigned_at timestamptz not null default now(),
  primary key(match_id,user_id)
);

create table if not exists public.arena_integrity_events (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.arena_matches(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  round_id uuid references public.arena_rounds(id) on delete set null,
  event_type text not null check (event_type in ('tab_hidden','tab_visible','window_blur','window_focus','fullscreen_exit','fullscreen_enter','disconnect','reconnect','network_change','duplicate_session','suspicious_timing')),
  severity smallint not null default 1 check (severity between 1 and 5),
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.arena_integrity_summaries (
  match_id uuid not null references public.arena_matches(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  event_count integer not null default 0,
  weighted_events integer not null default 0,
  integrity_score numeric not null default 100 check (integrity_score between 0 and 100),
  status text not null default 'clear' check (status in ('clear','review','flagged','disqualified')),
  reviewed_by uuid references public.profiles(id) on delete set null,
  review_notes text,
  reviewed_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key(match_id,user_id)
);

create table if not exists public.arena_reward_rules (
  id uuid primary key default gen_random_uuid(),
  match_id uuid references public.arena_matches(id) on delete cascade,
  tournament_id uuid references public.arena_tournaments(id) on delete cascade,
  placement integer not null check (placement >= 1),
  reward_type text not null check (reward_type in ('coins','badge','cash','achievement')),
  coin_amount integer,
  cash_amount numeric,
  currency text not null default 'ETB',
  badge_id uuid references public.badges(id) on delete set null,
  achievement_title text,
  created_by uuid references public.profiles(id) on delete set null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  check (((match_id is not null)::int + (tournament_id is not null)::int) = 1),
  check (coin_amount is null or coin_amount >= 0),
  check (cash_amount is null or cash_amount >= 0)
);

create table if not exists public.arena_rewards (
  id uuid primary key default gen_random_uuid(),
  rule_id uuid references public.arena_reward_rules(id) on delete set null,
  match_id uuid references public.arena_matches(id) on delete set null,
  tournament_id uuid references public.arena_tournaments(id) on delete set null,
  beneficiary_user_id uuid references public.profiles(id) on delete cascade,
  beneficiary_arena_team_id uuid references public.arena_teams(id) on delete set null,
  beneficiary_tournament_team_id uuid references public.arena_tournament_teams(id) on delete set null,
  reward_type text not null check (reward_type in ('coins','badge','cash','achievement')),
  coin_amount integer,
  cash_amount numeric,
  currency text not null default 'ETB',
  badge_id uuid references public.badges(id) on delete set null,
  achievement_title text,
  status text not null default 'pending' check (status in ('pending','available','paid','cancelled')),
  external_ref text,
  created_at timestamptz not null default now(),
  available_at timestamptz,
  paid_at timestamptz,
  check (((beneficiary_user_id is not null)::int + (beneficiary_arena_team_id is not null)::int + (beneficiary_tournament_team_id is not null)::int) = 1)
);

create table if not exists public.career_passport_achievements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  achievement_type text not null check (achievement_type in ('arena','challenge','academy','employer','community','other')),
  title text not null,
  issuer text not null default 'Mela',
  description text,
  source_table text,
  source_id uuid,
  placement integer,
  score numeric,
  verified boolean not null default false,
  verified_by uuid references public.profiles(id) on delete set null,
  verified_at timestamptz,
  evidence_url text,
  metadata jsonb not null default '{}'::jsonb,
  is_public boolean not null default true,
  created_at timestamptz not null default now()
);
create unique index if not exists career_passport_achievement_source_uq on public.career_passport_achievements(user_id,source_table,source_id,title) where source_id is not null;

create table if not exists public.arena_daily_metrics (
  metric_date date not null,
  arena_type text not null,
  matches_created integer not null default 0,
  matches_started integer not null default 0,
  matches_completed integer not null default 0,
  unique_participants integer not null default 0,
  submissions integer not null default 0,
  average_score numeric,
  updated_at timestamptz not null default now(),
  primary key(metric_date,arena_type)
);

create index if not exists arena_seasons_status_dates_idx on public.arena_seasons(status,starts_at,ends_at);
create index if not exists arena_tournaments_status_start_idx on public.arena_tournaments(status,starts_at);
create index if not exists arena_tournaments_season_idx on public.arena_tournaments(season_id);
create index if not exists arena_tournament_teams_tournament_idx on public.arena_tournament_teams(tournament_id);
create index if not exists arena_tournament_team_members_user_idx on public.arena_tournament_team_members(user_id);
create index if not exists arena_tournament_competitors_tournament_status_idx on public.arena_tournament_competitors(tournament_id,status);
create index if not exists arena_tournament_rounds_tournament_idx on public.arena_tournament_rounds(tournament_id,round_no);
create index if not exists arena_tournament_pairings_round_idx on public.arena_tournament_pairings(tournament_round_id,status);
create index if not exists arena_tournament_pairings_match_idx on public.arena_tournament_pairings(arena_match_id);
create index if not exists arena_matches_season_idx on public.arena_matches(season_id);
create index if not exists arena_matches_tournament_idx on public.arena_matches(tournament_id);
create index if not exists arena_matches_pairing_idx on public.arena_matches(tournament_pairing_id);
create index if not exists arena_rating_history_user_date_idx on public.arena_rating_history(user_id,created_at desc);
create index if not exists arena_rating_history_type_date_idx on public.arena_rating_history(arena_type,created_at desc);
create index if not exists arena_matchmaking_waiting_idx on public.arena_matchmaking_queue(arena_type,assessment_id,rating_snapshot,created_at) where status='waiting';
create index if not exists arena_judges_user_idx on public.arena_judges(user_id,status);
create index if not exists arena_integrity_events_match_user_idx on public.arena_integrity_events(match_id,user_id,created_at);
create index if not exists arena_integrity_events_round_idx on public.arena_integrity_events(round_id);
create index if not exists arena_integrity_summaries_user_idx on public.arena_integrity_summaries(user_id,status);
create index if not exists arena_reward_rules_match_idx on public.arena_reward_rules(match_id,placement) where active=true;
create index if not exists arena_reward_rules_tournament_idx on public.arena_reward_rules(tournament_id,placement) where active=true;
create index if not exists arena_rewards_user_idx on public.arena_rewards(beneficiary_user_id,created_at desc);
create index if not exists arena_rewards_match_idx on public.arena_rewards(match_id);
create index if not exists arena_rewards_tournament_idx on public.arena_rewards(tournament_id);
create index if not exists career_passport_achievements_user_idx on public.career_passport_achievements(user_id,created_at desc);

alter table public.arena_seasons enable row level security;
alter table public.arena_tournaments enable row level security;
alter table public.arena_tournament_teams enable row level security;
alter table public.arena_tournament_team_members enable row level security;
alter table public.arena_tournament_competitors enable row level security;
alter table public.arena_tournament_rounds enable row level security;
alter table public.arena_tournament_pairings enable row level security;
alter table public.arena_player_ratings enable row level security;
alter table public.arena_rating_history enable row level security;
alter table public.arena_matchmaking_queue enable row level security;
alter table public.arena_judges enable row level security;
alter table public.arena_integrity_events enable row level security;
alter table public.arena_integrity_summaries enable row level security;
alter table public.arena_reward_rules enable row level security;
alter table public.arena_rewards enable row level security;
alter table public.career_passport_achievements enable row level security;
alter table public.arena_daily_metrics enable row level security;

revoke all on public.arena_seasons, public.arena_tournaments, public.arena_tournament_teams, public.arena_tournament_team_members, public.arena_tournament_competitors, public.arena_tournament_rounds, public.arena_tournament_pairings, public.arena_player_ratings, public.arena_rating_history, public.arena_matchmaking_queue, public.arena_judges, public.arena_integrity_events, public.arena_integrity_summaries, public.arena_reward_rules, public.arena_rewards, public.career_passport_achievements, public.arena_daily_metrics from anon, authenticated;
grant select on public.arena_seasons, public.arena_tournaments, public.arena_player_ratings, public.arena_daily_metrics to anon, authenticated;
grant select on public.arena_tournament_teams, public.arena_tournament_team_members, public.arena_tournament_competitors, public.arena_tournament_rounds, public.arena_tournament_pairings, public.arena_rating_history, public.arena_matchmaking_queue, public.arena_judges, public.arena_integrity_events, public.arena_integrity_summaries, public.arena_reward_rules, public.arena_rewards, public.career_passport_achievements to authenticated;
grant select,insert,update,delete on all tables in schema public to service_role;

create policy "Arena seasons public read" on public.arena_seasons for select to anon,authenticated using (visibility='public' and status in ('open','active','completed') or created_by=(select auth.uid()) or private.is_admin_user());
create policy "Arena tournaments public read" on public.arena_tournaments for select to anon,authenticated using (visibility='public' and status in ('registration','in_progress','completed') or created_by=(select auth.uid()) or private.is_admin_user());
create policy "Arena tournament teams readable" on public.arena_tournament_teams for select to authenticated using (captain_id=(select auth.uid()) or exists(select 1 from public.arena_tournament_team_members tm where tm.team_id=id and tm.user_id=(select auth.uid())) or exists(select 1 from public.arena_tournaments t where t.id=tournament_id and (t.visibility='public' or t.created_by=(select auth.uid()))) or private.is_admin_user());
create policy "Arena tournament team members readable" on public.arena_tournament_team_members for select to authenticated using (user_id=(select auth.uid()) or exists(select 1 from public.arena_tournament_teams t where t.id=team_id and (t.captain_id=(select auth.uid()) or exists(select 1 from public.arena_tournaments tr where tr.id=t.tournament_id and tr.created_by=(select auth.uid())))) or private.is_admin_user());
create policy "Arena tournament competitors readable" on public.arena_tournament_competitors for select to authenticated using (user_id=(select auth.uid()) or exists(select 1 from public.arena_tournament_team_members tm where tm.team_id=tournament_team_id and tm.user_id=(select auth.uid())) or exists(select 1 from public.arena_tournaments t where t.id=tournament_id and (t.visibility='public' or t.created_by=(select auth.uid()))) or private.is_admin_user());
create policy "Arena tournament rounds readable" on public.arena_tournament_rounds for select to authenticated using (exists(select 1 from public.arena_tournaments t where t.id=tournament_id and (t.visibility='public' or t.created_by=(select auth.uid()) or exists(select 1 from public.arena_tournament_competitors c left join public.arena_tournament_team_members tm on tm.team_id=c.tournament_team_id where c.tournament_id=t.id and (c.user_id=(select auth.uid()) or tm.user_id=(select auth.uid()))))) or private.is_admin_user());
create policy "Arena tournament pairings readable" on public.arena_tournament_pairings for select to authenticated using (exists(select 1 from public.arena_tournament_rounds r join public.arena_tournaments t on t.id=r.tournament_id where r.id=tournament_round_id and (t.visibility='public' or t.created_by=(select auth.uid()))) or private.is_admin_user());
create policy "Arena ratings public read" on public.arena_player_ratings for select to anon,authenticated using (true);
create policy "Arena rating history own read" on public.arena_rating_history for select to authenticated using (user_id=(select auth.uid()) or private.is_admin_user());
create policy "Arena matchmaking own read" on public.arena_matchmaking_queue for select to authenticated using (user_id=(select auth.uid()) or private.is_admin_user());
create policy "Arena judges readable" on public.arena_judges for select to authenticated using (user_id=(select auth.uid()) or assigned_by=(select auth.uid()) or private.can_read_arena_match(match_id) or private.is_admin_user());
create policy "Arena integrity events readable" on public.arena_integrity_events for select to authenticated using (user_id=(select auth.uid()) or exists(select 1 from public.arena_matches m where m.id=match_id and m.creator_id=(select auth.uid())) or private.is_admin_user());
create policy "Arena integrity summaries readable" on public.arena_integrity_summaries for select to authenticated using (user_id=(select auth.uid()) or exists(select 1 from public.arena_matches m where m.id=match_id and m.creator_id=(select auth.uid())) or private.is_admin_user());
create policy "Arena reward rules readable" on public.arena_reward_rules for select to authenticated using (exists(select 1 from public.arena_matches m where m.id=match_id and (m.creator_id=(select auth.uid()) or private.can_read_arena_match(m.id))) or exists(select 1 from public.arena_tournaments t where t.id=tournament_id and (t.visibility='public' or t.created_by=(select auth.uid()))) or private.is_admin_user());
create policy "Arena rewards readable" on public.arena_rewards for select to authenticated using (beneficiary_user_id=(select auth.uid()) or exists(select 1 from public.arena_teams t join public.arena_team_members tm on tm.team_id=t.id where t.id=beneficiary_arena_team_id and tm.user_id=(select auth.uid())) or exists(select 1 from public.arena_tournament_team_members tm where tm.team_id=beneficiary_tournament_team_id and tm.user_id=(select auth.uid())) or private.is_admin_user());
create policy "Career passport achievements public or own" on public.career_passport_achievements for select to authenticated using (user_id=(select auth.uid()) or is_public=true or private.is_admin_user());
create policy "Arena daily metrics public read" on public.arena_daily_metrics for select to anon,authenticated using (true);
;
