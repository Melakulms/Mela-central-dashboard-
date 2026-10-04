-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260920110648

create unique index if not exists arena_teams_one_captain_per_match_uidx
on public.arena_teams(match_id,captain_id)
where captain_id is not null;

create or replace function private.create_arena(
  p_title text, p_arena_type text, p_visibility text, p_assessment_id uuid,
  p_max_participants integer, p_team_mode boolean, p_scheduled_at timestamptz
) returns uuid
language plpgsql security definer set search_path to ''
as $$
declare v_uid uuid := (select auth.uid()); v_id uuid;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if nullif(trim(coalesce(p_title,'')),'') is null then raise exception 'arena title is required'; end if;
  if p_arena_type not in ('quiz_battle','speed_quiz','interview_practice','case_sprint','team_battle','skill_sprint','employer_challenge') then raise exception 'unsupported arena type'; end if;
  if coalesce(p_visibility,'public') not in ('public','private','invite') then raise exception 'invalid arena visibility'; end if;
  if p_scheduled_at is not null and p_scheduled_at < now() then raise exception 'scheduled time must be in the future'; end if;
  insert into public.arena_matches(title,arena_type,creator_id,visibility,assessment_id,max_participants,min_participants,team_mode,scheduled_at,status,scoring_mode)
  values(trim(p_title),p_arena_type,v_uid,coalesce(p_visibility,'public'),p_assessment_id,
         greatest(1,least(coalesce(p_max_participants,2),100)),
         case when coalesce(p_max_participants,2)=1 then 1 else 2 end,
         coalesce(p_team_mode,false),p_scheduled_at,'open',
         case when p_arena_type in ('quiz_battle','speed_quiz') then 'auto' else 'judge' end)
  returning id into v_id;
  insert into public.arena_participants(match_id,user_id,status,ready) values(v_id,v_uid,'joined',false);
  return v_id;
end $$;

create or replace function private.create_arena_team(p_match_id uuid, p_name text)
returns public.arena_teams
language plpgsql security definer set search_path to ''
as $$
declare v_uid uuid := (select auth.uid()); v_m public.arena_matches; v public.arena_teams;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if nullif(trim(coalesce(p_name,'')),'') is null then raise exception 'team name is required'; end if;
  select * into v_m from public.arena_matches where id=p_match_id for update;
  if v_m.id is null or not v_m.team_mode or v_m.status not in ('open','ready') then raise exception 'joinable team arena required'; end if;
  if not exists(select 1 from public.arena_participants where match_id=p_match_id and user_id=v_uid and status='joined') then perform private.join_arena(p_match_id); end if;
  if exists(select 1 from public.arena_participants where match_id=p_match_id and user_id=v_uid and team_id is not null) then raise exception 'already assigned to an arena team'; end if;
  if exists(select 1 from public.arena_teams where match_id=p_match_id and captain_id=v_uid) then raise exception 'you already captain a team in this arena'; end if;
  insert into public.arena_teams(match_id,name,captain_id,join_code)
  values(p_match_id,trim(p_name),v_uid,upper(substr(md5(gen_random_uuid()::text),1,10)))
  returning * into v;
  insert into public.arena_team_members(team_id,user_id) values(v.id,v_uid);
  update public.arena_participants set team_id=v.id where match_id=p_match_id and user_id=v_uid;
  return v;
end $$;

create or replace function private.respond_arena_invite(p_invite_id uuid,p_accept boolean)
returns void
language plpgsql security definer set search_path to ''
as $$
declare v_uid uuid := (select auth.uid()); v_inv public.arena_invites; v_max integer; v_count integer;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select * into v_inv from public.arena_invites where id=p_invite_id and invited_user_id=v_uid and status='pending' for update;
  if v_inv.id is null then raise exception 'pending invitation not found'; end if;
  if not p_accept then
    update public.arena_invites set status='declined',responded_at=now() where id=p_invite_id;
    return;
  end if;
  perform 1 from public.arena_matches where id=v_inv.match_id and status in ('open','ready') for update;
  if not found then raise exception 'arena is not joinable'; end if;
  select max_participants into v_max from public.arena_matches where id=v_inv.match_id;
  select count(*) into v_count from public.arena_participants where match_id=v_inv.match_id and status in ('joined','active','finished');
  if v_count>=v_max then raise exception 'arena is full'; end if;
  insert into public.arena_participants(match_id,user_id,status,ready)
  values(v_inv.match_id,v_uid,'joined',false)
  on conflict(match_id,user_id) do update set status='joined',ready=false,joined_at=now();
  update public.arena_invites set status='accepted',responded_at=now() where id=p_invite_id;
end $$;

create or replace function private.register_arena_tournament(p_tournament_id uuid)
returns uuid
language plpgsql security definer set search_path to ''
as $$
declare v_uid uuid := (select auth.uid()); v_t public.arena_tournaments; v_id uuid; v_count integer;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select * into v_t from public.arena_tournaments where id=p_tournament_id for update;
  if v_t.id is null or v_t.status<>'registration' or v_t.team_mode then raise exception 'individual registration unavailable'; end if;
  if v_t.registration_deadline is not null and now()>v_t.registration_deadline then raise exception 'registration closed'; end if;
  if exists(select 1 from public.arena_tournament_competitors where tournament_id=p_tournament_id and user_id=v_uid and status<>'withdrawn') then
    select id into v_id from public.arena_tournament_competitors where tournament_id=p_tournament_id and user_id=v_uid;
    return v_id;
  end if;
  select count(*) into v_count from public.arena_tournament_competitors where tournament_id=p_tournament_id and status<>'withdrawn';
  if v_count>=v_t.max_competitors then raise exception 'tournament is full'; end if;
  insert into public.arena_tournament_competitors(tournament_id,user_id,status) values(p_tournament_id,v_uid,'registered')
  returning id into v_id;
  return v_id;
end $$;

create or replace function private.enforce_application_audience_access()
returns trigger
language plpgsql security definer set search_path to ''
as $$
declare v_stage text; v_role public.user_role; v_type public.opportunity_type; v_mode text;
begin
  select role,education_stage_key into v_role,v_stage from public.profiles where id=new.applicant_id;
  if v_role<>'student' then raise exception 'student profile required'; end if;
  if v_stage is null then raise exception 'complete your education stage before applying'; end if;
  select opportunity_type into v_type from public.opportunities where id=new.opportunity_id;
  select access_mode into v_mode from public.audience_opportunity_rules where stage_key=v_stage and opportunity_type=v_type;
  v_mode:=coalesce(v_mode,'hidden');
  if v_mode in ('hidden','view_only') then raise exception 'this opportunity type is not available for your education stage'; end if;
  if v_mode='adult_gate' and starts_with(v_stage,'school_') and not private.user_has_guardian_or_adult_clearance(new.applicant_id) then
    raise exception 'guardian verification or verified adult eligibility is required for school-stage work opportunities';
  end if;
  return new;
end $$;

;
