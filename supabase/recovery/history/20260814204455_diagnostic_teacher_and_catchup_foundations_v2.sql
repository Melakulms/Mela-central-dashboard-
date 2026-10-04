-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260814204455
create table if not exists public.learner_diagnostic_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  stage_key text not null references public.education_audience_stages(stage_key),
  diagnostic_type text not null default 'baseline' check (diagnostic_type in ('baseline','catchup','checkpoint','transition')),
  status text not null default 'in_progress' check (status in ('in_progress','completed','cancelled')),
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  summary jsonb not null default '{}'::jsonb
);
create index if not exists learner_diagnostic_sessions_user_idx on public.learner_diagnostic_sessions(user_id,started_at desc);
alter table public.learner_diagnostic_sessions enable row level security;
drop policy if exists learner_diagnostic_sessions_self on public.learner_diagnostic_sessions;
create policy learner_diagnostic_sessions_self on public.learner_diagnostic_sessions for all to authenticated using (user_id=(select auth.uid()) or private.is_admin_user()) with check (user_id=(select auth.uid()) or private.is_admin_user());
grant select,insert,update on public.learner_diagnostic_sessions to authenticated;
grant all on public.learner_diagnostic_sessions to service_role;

create table if not exists public.learner_diagnostic_results (
  session_id uuid not null references public.learner_diagnostic_sessions(id) on delete cascade,
  competency_id uuid not null references public.learning_competencies(id) on delete cascade,
  score numeric not null check (score between 0 and 100),
  confidence numeric not null default 0.5 check (confidence between 0 and 1),
  evidence_count integer not null default 1 check (evidence_count>=0),
  estimated_level text,
  created_at timestamptz not null default now(),
  primary key(session_id,competency_id)
);
alter table public.learner_diagnostic_results enable row level security;
drop policy if exists learner_diagnostic_results_self on public.learner_diagnostic_results;
create policy learner_diagnostic_results_self on public.learner_diagnostic_results for select to authenticated using (exists(select 1 from public.learner_diagnostic_sessions s where s.id=session_id and (s.user_id=(select auth.uid()) or private.is_admin_user())));
grant select on public.learner_diagnostic_results to authenticated;
grant all on public.learner_diagnostic_results to service_role;

create table if not exists public.learner_catchup_plans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  stage_key text not null references public.education_audience_stages(stage_key),
  title text not null,
  rationale text,
  duration_weeks smallint not null default 8 check (duration_weeks between 1 and 24),
  status text not null default 'active' check (status in ('draft','active','completed','cancelled')),
  created_at timestamptz not null default now(),
  completed_at timestamptz
);
create index if not exists learner_catchup_plans_user_idx on public.learner_catchup_plans(user_id,status,created_at desc);
alter table public.learner_catchup_plans enable row level security;
drop policy if exists learner_catchup_plans_self on public.learner_catchup_plans;
create policy learner_catchup_plans_self on public.learner_catchup_plans for select to authenticated using (user_id=(select auth.uid()) or private.is_admin_user());
grant select on public.learner_catchup_plans to authenticated;
grant all on public.learner_catchup_plans to service_role;

create table if not exists public.learner_catchup_plan_items (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.learner_catchup_plans(id) on delete cascade,
  competency_id uuid not null references public.learning_competencies(id) on delete cascade,
  week_number smallint not null check (week_number between 1 and 24),
  priority smallint not null default 1 check (priority between 1 and 5),
  target_score numeric not null default 70 check (target_score between 0 and 100),
  status text not null default 'planned' check (status in ('planned','in_progress','mastered','skipped')),
  notes text,
  unique(plan_id,competency_id)
);
alter table public.learner_catchup_plan_items enable row level security;
drop policy if exists learner_catchup_plan_items_self on public.learner_catchup_plan_items;
create policy learner_catchup_plan_items_self on public.learner_catchup_plan_items for select to authenticated using (exists(select 1 from public.learner_catchup_plans p where p.id=plan_id and (p.user_id=(select auth.uid()) or private.is_admin_user())));
grant select on public.learner_catchup_plan_items to authenticated;
grant all on public.learner_catchup_plan_items to service_role;

create table if not exists public.educator_profiles (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  educator_type text not null default 'teacher' check (educator_type in ('teacher','school_leader','tvet_instructor','lecturer','counselor','learning_support')),
  institution_name text,
  specialization text,
  verified boolean not null default false,
  verified_by uuid references public.profiles(id),
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.educator_profiles enable row level security;
drop policy if exists educator_profiles_self on public.educator_profiles;
create policy educator_profiles_self on public.educator_profiles for select to authenticated using (user_id=(select auth.uid()) or private.is_admin_user());
drop policy if exists educator_profiles_admin_write on public.educator_profiles;
create policy educator_profiles_admin_write on public.educator_profiles for all to authenticated using (private.is_admin_user()) with check (private.is_admin_user());
grant select on public.educator_profiles to authenticated;
grant all on public.educator_profiles to service_role;

create table if not exists public.educator_classrooms (
  id uuid primary key default gen_random_uuid(),
  educator_id uuid not null references public.profiles(id) on delete cascade,
  stage_key text not null references public.education_audience_stages(stage_key),
  title text not null,
  institution_name text,
  academic_year text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists educator_classrooms_educator_idx on public.educator_classrooms(educator_id,active);
alter table public.educator_classrooms enable row level security;
drop policy if exists educator_classrooms_owner on public.educator_classrooms;
create policy educator_classrooms_owner on public.educator_classrooms for all to authenticated using (educator_id=(select auth.uid()) or private.is_admin_user()) with check (educator_id=(select auth.uid()) or private.is_admin_user());
grant select,insert,update,delete on public.educator_classrooms to authenticated;
grant all on public.educator_classrooms to service_role;

create table if not exists public.educator_classroom_learners (
  classroom_id uuid not null references public.educator_classrooms(id) on delete cascade,
  learner_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'active' check (status in ('invited','active','removed')),
  joined_at timestamptz,
  primary key(classroom_id,learner_id)
);
alter table public.educator_classroom_learners enable row level security;
drop policy if exists educator_classroom_learners_access on public.educator_classroom_learners;
create policy educator_classroom_learners_access on public.educator_classroom_learners for select to authenticated using (learner_id=(select auth.uid()) or private.is_admin_user() or exists(select 1 from public.educator_classrooms c where c.id=classroom_id and c.educator_id=(select auth.uid())));
grant select on public.educator_classroom_learners to authenticated;
grant all on public.educator_classroom_learners to service_role;

create table if not exists public.learner_support_signals (
  id uuid primary key default gen_random_uuid(),
  learner_id uuid not null references public.profiles(id) on delete cascade,
  competency_id uuid references public.learning_competencies(id) on delete cascade,
  signal_type text not null check (signal_type in ('mastery_gap','practice_inactivity','repeated_difficulty','transition_risk','attendance_signal','wellbeing_referral')),
  severity text not null default 'attention' check (severity in ('info','attention','priority')),
  title text not null,
  explanation text not null,
  status text not null default 'open' check (status in ('open','acknowledged','resolved','dismissed')),
  source text not null default 'mela',
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);
create index if not exists learner_support_signals_learner_idx on public.learner_support_signals(learner_id,status,created_at desc);
alter table public.learner_support_signals enable row level security;
drop policy if exists learner_support_signals_read on public.learner_support_signals;
create policy learner_support_signals_read on public.learner_support_signals for select to authenticated using (learner_id=(select auth.uid()) or private.is_admin_user() or exists(select 1 from public.educator_classroom_learners cl join public.educator_classrooms c on c.id=cl.classroom_id where cl.learner_id=learner_support_signals.learner_id and cl.status='active' and c.educator_id=(select auth.uid())));
grant select on public.learner_support_signals to authenticated;
grant all on public.learner_support_signals to service_role;

create or replace function public.get_my_learning_journey()
returns jsonb language sql stable security invoker set search_path=''
as $function$
select jsonb_build_object(
 'audience',public.get_my_audience_context(),
 'mastery',public.get_my_mastery_engine(),
 'opportunity_graph',case when public.my_audience_feature_access('opportunities') in ('enabled','limited','adult_gate') then public.get_my_opportunity_graph() else '{}'::jsonb end,
 'diagnostics',(select coalesce(jsonb_agg(to_jsonb(x) order by x.started_at desc),'[]'::jsonb) from (select id,stage_key,diagnostic_type,status,started_at,completed_at,summary from public.learner_diagnostic_sessions where user_id=(select auth.uid()) order by started_at desc limit 10) x),
 'catchup_plans',(select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) from (select id,stage_key,title,rationale,duration_weeks,status,created_at,completed_at from public.learner_catchup_plans where user_id=(select auth.uid()) order by created_at desc limit 5) x)
);
$function$;
revoke all on function public.get_my_learning_journey() from public,anon;
grant execute on function public.get_my_learning_journey() to authenticated,service_role;
;
