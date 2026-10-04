-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260813085841
-- Central authoritative feature gates for Mela.

insert into public.platform_feature_flags(feature_key,label,description,enabled,maintenance_message,config)
values
 ('platform_live','Platform Live','Master kill switch for end-user feature access.',true,'Mela is temporarily unavailable while we perform maintenance.','{}'::jsonb),
 ('payments','Course Payments','Allows creation and verification of new course payment checkouts.',true,'Payments are temporarily unavailable.','{}'::jsonb)
on conflict (feature_key) do nothing;

create or replace function public.platform_feature_enabled(p_feature_key text)
returns boolean
language sql
stable
security invoker
set search_path='pg_catalog','public'
as $$
  select coalesce((select f.enabled from public.platform_feature_flags f where f.feature_key=p_feature_key),false)
$$;

create or replace function public.platform_feature_available(p_feature_key text)
returns boolean
language sql
stable
security invoker
set search_path='pg_catalog','public'
as $$
  select case when p_feature_key='platform_live'
    then public.platform_feature_enabled('platform_live')
    else public.platform_feature_enabled('platform_live') and public.platform_feature_enabled(p_feature_key)
  end
$$;

revoke all on function public.platform_feature_enabled(text) from public;
revoke all on function public.platform_feature_available(text) from public;
grant execute on function public.platform_feature_enabled(text) to anon,authenticated,service_role;
grant execute on function public.platform_feature_available(text) to anon,authenticated,service_role;

-- Add a restrictive policy to a table without disturbing its existing permissive ownership policies.
do $$
declare r record; p_name text;
begin
  for r in
    select * from (values
      ('career_passport','profile_education'),('career_passport','profile_experience'),('career_passport','profile_projects'),('career_passport','profile_languages'),('career_passport','profile_documents'),('career_passport','career_passport_entries'),('career_passport','career_passport_achievements'),('career_passport','verified_skills'),('career_passport','badges'),('career_passport','user_badges'),
      ('academy','career_paths'),('academy','path_modules'),('academy','path_lessons'),('academy','path_lesson_translations'),('academy','path_module_resources'),('academy','career_path_enrollments'),('academy','student_module_progress'),('academy','student_lesson_progress'),('academy','skill_academy_certificates'),('academy','courses'),('academy','course_lessons'),('academy','course_enrollments'),('academy','lesson_progress'),
      ('practice','practice_topics'),('practice','practice_questions'),('practice','practice_sessions'),('practice','practice_session_questions'),('practice','practice_attempts'),('practice','practice_mastery'),('practice','practice_user_stats'),
      ('assessments','skill_assessments'),('assessments','skill_assessment_results'),('assessments','assessment_questions'),('assessments','assessment_attempts'),('assessments','assessment_attempt_questions'),('assessments','assessment_responses'),('assessments','proctor_reviews'),('assessments','proctor_audit_logs'),('assessments','proctored_exams'),('assessments','exam_results'),
      ('arena','arena_matches'),('arena','arena_participants'),('arena','arena_rounds'),('arena','arena_round_submissions'),('arena','arena_teams'),('arena','arena_team_members'),('arena','arena_invites'),('arena','arena_player_ratings'),('arena','arena_rating_history'),('arena','arena_matchmaking_queue'),('arena','arena_integrity_events'),('arena','arena_integrity_summaries'),('arena','arena_judges'),('arena','arena_seasons'),('arena','arena_tournaments'),('arena','arena_tournament_competitors'),('arena','arena_tournament_rounds'),('arena','arena_tournament_pairings'),('arena','arena_tournament_teams'),('arena','arena_tournament_team_members'),('arena','arena_reward_rules'),('arena','arena_rewards'),('arena','arena_daily_metrics'),
      ('challenges','sponsored_challenges'),('challenges','challenge_participants'),('challenges','challenge_teams'),('challenges','challenge_team_members'),('challenges','challenge_submissions'),('challenges','challenge_judges'),('challenges','challenge_reviews'),('challenges','challenge_rewards'),
      ('opportunities','opportunities'),('opportunities','applications'),('opportunities','application_notes'),('opportunities','application_status_history'),('opportunities','candidate_matches'),('opportunities','interviews'),('opportunities','interview_candidate_responses'),('opportunities','saved_opportunities'),('opportunities','opportunity_reminders'),('opportunities','opportunity_screening_questions'),('opportunities','opportunity_templates'),('opportunities','opportunity_matching_configs'),
      ('scholarships','scholarship_details'),
      ('earn_work','marketplace_tasks'),('earn_work','marketplace_submissions'),('earn_work','freelance_contracts'),('earn_work','task_milestones'),('earn_work','task_messages'),('earn_work','work_reviews'),('earn_work','work_reputation'),('earn_work','employer_work_reputation'),
      ('payouts','payout_accounts'),('payouts','payout_requests'),('payouts','escrow_transactions'),('payouts','escrow_payment_attempts'),
      ('mentorship','mentor_profiles'),('mentorship','mentor_availability'),('mentorship','mentorship_requests'),('mentorship','mentorship_sessions'),
      ('video_calls','video_call_rooms'),('video_calls','video_call_participants'),('video_calls','video_call_presence'),('video_calls','video_call_signals'),('video_calls','video_call_events'),
      ('ai_career_coach','career_coach_sessions'),('ai_career_coach','career_coach_messages'),('ai_career_coach','career_coach_action_plans'),('ai_career_coach','career_coach_action_items'),('ai_career_coach','career_coach_usage'),
      ('ai_tutor','ai_tutor_usage'),('ai_tutor','ai_coach_sessions'),('ai_tutor','ai_coach_messages')
    ) as x(feature_key,table_name)
    where to_regclass('public.'||x.table_name) is not null
  loop
    execute format('alter table public.%I enable row level security',r.table_name);
    p_name := 'mela_gate_'||r.feature_key;
    execute format('drop policy if exists %I on public.%I',p_name,r.table_name);
    execute format(
      'create policy %I on public.%I as restrictive for all to anon, authenticated using (public.platform_feature_available(%L)) with check (public.platform_feature_available(%L))',
      p_name,r.table_name,r.feature_key,r.feature_key
    );
  end loop;
end $$;

-- Registration is blocked at the Auth transaction itself when disabled or the platform is offline.
create or replace function private.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_provider text;
  v_name text;
  v_avatar text;
begin
  if not public.platform_feature_available('registrations') then
    raise exception 'Mela registrations are temporarily disabled by the platform administrator.' using errcode='P0001';
  end if;

  v_provider := coalesce(
    nullif(new.raw_app_meta_data ->> 'provider',''),
    case when new.phone is not null then 'phone' when new.email is not null then 'email' else 'unknown' end
  );
  v_name := coalesce(
    nullif(new.raw_user_meta_data ->> 'full_name',''),
    nullif(new.raw_user_meta_data ->> 'name',''),
    nullif(split_part(coalesce(new.email,''),'@',1),''),
    case when new.phone is not null then 'Mela User ' || right(new.phone,4) end,
    'Mela User'
  );
  v_avatar := coalesce(
    nullif(new.raw_user_meta_data ->> 'avatar_url',''),
    nullif(new.raw_user_meta_data ->> 'picture','')
  );

  insert into public.profiles (
    id, full_name, email, phone_number, avatar_url, preferred_language,
    auth_primary_method, auth_provider, email_verified, phone_verified
  ) values (
    new.id,
    v_name,
    nullif(new.email,''),
    nullif(new.phone,''),
    v_avatar,
    coalesce(nullif(new.raw_user_meta_data ->> 'preferred_language',''), nullif(new.raw_user_meta_data ->> 'language',''), 'English'),
    case when v_provider='phone' then 'phone' when v_provider='google' then 'google' else 'email' end,
    v_provider,
    (nullif(new.email,'') is not null and new.email_confirmed_at is not null),
    (nullif(new.phone,'') is not null and new.phone_confirmed_at is not null)
  )
  on conflict (id) do update set
    full_name=coalesce(nullif(public.profiles.full_name,''), excluded.full_name),
    email=coalesce(excluded.email, public.profiles.email),
    phone_number=coalesce(excluded.phone_number, public.profiles.phone_number),
    avatar_url=coalesce(public.profiles.avatar_url, excluded.avatar_url),
    preferred_language=coalesce(public.profiles.preferred_language, excluded.preferred_language),
    auth_primary_method=coalesce(public.profiles.auth_primary_method, excluded.auth_primary_method),
    auth_provider=coalesce(excluded.auth_provider, public.profiles.auth_provider),
    email_verified=(public.profiles.email_verified or excluded.email_verified),
    phone_verified=(public.profiles.phone_verified or excluded.phone_verified),
    updated_at=now();

  insert into public.notification_preferences(user_id)
  values(new.id)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

-- Cron wrappers keep jobs scheduled but make lifecycle automation obey founder switches.
create or replace function private.gated_process_due_opportunity_reminders()
returns integer language plpgsql security definer set search_path='' as $$
begin
  if not public.platform_feature_available('opportunities') then return 0; end if;
  return private.process_due_opportunity_reminders();
end $$;
create or replace function private.gated_advance_sponsored_challenge_lifecycle()
returns integer language plpgsql security definer set search_path='' as $$
begin
  if not public.platform_feature_available('challenges') then return 0; end if;
  return private.advance_sponsored_challenge_lifecycle();
end $$;
create or replace function private.gated_advance_arena_rounds()
returns integer language plpgsql security definer set search_path='' as $$
begin
  if not public.platform_feature_available('arena') then return 0; end if;
  return private.advance_arena_rounds();
end $$;
create or replace function private.gated_process_arena_matchmaking()
returns integer language plpgsql security definer set search_path='' as $$
begin
  if not public.platform_feature_available('arena') then return 0; end if;
  return private.process_arena_matchmaking();
end $$;
create or replace function private.gated_refresh_arena_daily_metrics(p_date date default current_date)
returns void language plpgsql security definer set search_path='' as $$
begin
  if not public.platform_feature_available('arena') then return; end if;
  perform private.refresh_arena_daily_metrics(p_date);
end $$;
create or replace function private.gated_advance_arena_season_lifecycle()
returns integer language plpgsql security definer set search_path='' as $$
begin
  if not public.platform_feature_available('arena') then return 0; end if;
  return private.advance_arena_season_lifecycle();
end $$;

select cron.alter_job((select jobid from cron.job where jobname='mela-opportunity-reminders'), command=>'select private.gated_process_due_opportunity_reminders();');
select cron.alter_job((select jobid from cron.job where jobname='mela-sponsored-challenge-lifecycle'), command=>'select private.gated_advance_sponsored_challenge_lifecycle();');
select cron.alter_job((select jobid from cron.job where jobname='mela-arena-round-lifecycle'), command=>'select private.gated_advance_arena_rounds();');
select cron.alter_job((select jobid from cron.job where jobname='mela-arena-matchmaking'), command=>'select private.gated_process_arena_matchmaking();');
select cron.alter_job((select jobid from cron.job where jobname='mela-arena-metrics'), command=>'select private.gated_refresh_arena_daily_metrics(current_date);');
select cron.alter_job((select jobid from cron.job where jobname='mela-arena-season-lifecycle'), command=>'select private.gated_advance_arena_season_lifecycle();');

;
