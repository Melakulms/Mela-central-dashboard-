-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812202550
-- Mela full platform database expansion
-- Non-destructive: preserves all existing data and tables.

create schema if not exists private;

-- 1) Enrich the core profile and employer records
alter table public.profiles
  add column if not exists city text,
  add column if not exists availability_status text default 'open_to_opportunities',
  add column if not exists portfolio_url text,
  add column if not exists linkedin_url text,
  add column if not exists github_url text;

alter table public.employers
  add column if not exists description text,
  add column if not exists logo_url text,
  add column if not exists contact_email text,
  add column if not exists phone_number text,
  add column if not exists headquarters text,
  add column if not exists sector_category public.launch_category,
  add column if not exists verification_status text not null default 'pending',
  add column if not exists verified_at timestamptz;

alter table public.opportunities
  add column if not exists skills_required text[] not null default '{}',
  add column if not exists experience_level text,
  add column if not exists education_level text,
  add column if not exists salary_min numeric(14,2),
  add column if not exists salary_max numeric(14,2),
  add column if not exists salary_currency text default 'ETB';

alter table public.applications
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists reviewed_at timestamptz,
  add column if not exists reviewer_id uuid references public.profiles(id) on delete set null;

-- 2) Career Passport detail tables
create table if not exists public.profile_education (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  institution text not null,
  qualification text,
  field_of_study text,
  start_year int,
  end_year int,
  is_current boolean not null default false,
  grade text,
  description text,
  verified boolean not null default false,
  verification_source text,
  is_public boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profile_education_years_chk check (start_year is null or end_year is null or end_year >= start_year)
);

create table if not exists public.profile_experience (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  organization text not null,
  title text not null,
  experience_type text default 'work',
  start_date date,
  end_date date,
  is_current boolean not null default false,
  description text,
  verified boolean not null default false,
  verification_source text,
  is_public boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profile_experience_dates_chk check (start_date is null or end_date is null or end_date >= start_date)
);

create table if not exists public.profile_projects (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  description text,
  project_url text,
  repository_url text,
  skill_tags text[] not null default '{}',
  started_at date,
  completed_at date,
  is_public boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.profile_languages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  language text not null,
  proficiency text not null,
  verified boolean not null default false,
  created_at timestamptz not null default now(),
  unique(user_id, language)
);

create table if not exists public.profile_documents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  document_type text not null,
  title text not null,
  file_url text not null,
  issuer text,
  issued_on date,
  expires_on date,
  verified boolean not null default false,
  is_public boolean not null default false,
  created_at timestamptz not null default now()
);

-- 3) Structured skill assessments
create table if not exists public.skill_assessments (
  id uuid primary key default gen_random_uuid(),
  skill_id uuid references public.skills(id) on delete set null,
  category public.launch_category,
  title text not null,
  description text,
  duration_minutes int not null default 30,
  pass_score int not null default 70,
  max_attempts int not null default 3,
  is_proctored boolean not null default false,
  status text not null default 'draft',
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint skill_assessments_pass_score_chk check (pass_score between 0 and 100),
  constraint skill_assessments_status_chk check (status in ('draft','published','archived'))
);

create table if not exists public.assessment_questions (
  id uuid primary key default gen_random_uuid(),
  assessment_id uuid not null references public.skill_assessments(id) on delete cascade,
  question_order int not null,
  prompt text not null,
  question_type text not null default 'single_choice',
  choices jsonb not null default '[]'::jsonb,
  points numeric(8,2) not null default 1,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(assessment_id, question_order)
);

create table if not exists private.assessment_answer_keys (
  question_id uuid primary key references public.assessment_questions(id) on delete cascade,
  correct_answer jsonb not null,
  explanation text,
  updated_at timestamptz not null default now()
);

create table if not exists public.assessment_attempts (
  id uuid primary key default gen_random_uuid(),
  assessment_id uuid not null references public.skill_assessments(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  attempt_no int not null default 1,
  status text not null default 'in_progress',
  started_at timestamptz not null default now(),
  submitted_at timestamptz,
  duration_seconds int,
  score numeric(6,2),
  passed boolean,
  proctored boolean not null default false,
  integrity_score numeric(5,2),
  metadata jsonb not null default '{}'::jsonb,
  unique(assessment_id, user_id, attempt_no),
  constraint assessment_attempt_status_chk check (status in ('in_progress','submitted','graded','void')),
  constraint assessment_attempt_score_chk check (score is null or score between 0 and 100),
  constraint assessment_integrity_score_chk check (integrity_score is null or integrity_score between 0 and 100)
);

create table if not exists public.assessment_responses (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null references public.assessment_attempts(id) on delete cascade,
  question_id uuid not null references public.assessment_questions(id) on delete cascade,
  response jsonb not null default 'null'::jsonb,
  answered_at timestamptz not null default now(),
  unique(attempt_id, question_id)
);

alter table public.proctor_audit_logs
  add column if not exists attempt_id uuid references public.assessment_attempts(id) on delete cascade,
  add column if not exists event_type text,
  add column if not exists details jsonb not null default '{}'::jsonb;

-- 4) Employer teams, matching, shortlists and interviews
create table if not exists public.employer_members (
  id uuid primary key default gen_random_uuid(),
  employer_id uuid not null references public.employers(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  member_role text not null default 'recruiter',
  status text not null default 'active',
  invited_at timestamptz not null default now(),
  joined_at timestamptz,
  unique(employer_id, user_id),
  constraint employer_member_role_chk check (member_role in ('owner','admin','recruiter','viewer')),
  constraint employer_member_status_chk check (status in ('invited','active','disabled'))
);

create table if not exists public.saved_candidates (
  id uuid primary key default gen_random_uuid(),
  employer_id uuid not null references public.employers(id) on delete cascade,
  candidate_id uuid not null references public.profiles(id) on delete cascade,
  saved_by uuid not null references public.profiles(id) on delete cascade,
  note text,
  created_at timestamptz not null default now(),
  unique(employer_id, candidate_id)
);

create table if not exists public.candidate_matches (
  id uuid primary key default gen_random_uuid(),
  employer_id uuid not null references public.employers(id) on delete cascade,
  opportunity_id uuid references public.opportunities(id) on delete cascade,
  candidate_id uuid not null references public.profiles(id) on delete cascade,
  match_score numeric(5,2) not null default 0,
  matched_skills text[] not null default '{}',
  missing_skills text[] not null default '{}',
  reasons jsonb not null default '[]'::jsonb,
  status text not null default 'recommended',
  generated_at timestamptz not null default now(),
  unique(opportunity_id, candidate_id),
  constraint candidate_match_score_chk check (match_score between 0 and 100),
  constraint candidate_match_status_chk check (status in ('recommended','viewed','saved','dismissed','contacted'))
);

create table if not exists public.interviews (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references public.applications(id) on delete cascade,
  scheduled_by uuid references public.profiles(id) on delete set null,
  starts_at timestamptz not null,
  ends_at timestamptz,
  mode text not null default 'online',
  meeting_url text,
  location text,
  status text not null default 'scheduled',
  employer_notes text,
  candidate_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint interview_dates_chk check (ends_at is null or ends_at > starts_at),
  constraint interview_status_chk check (status in ('scheduled','completed','cancelled','no_show','rescheduled'))
);

-- 5) Freelance contracts and milestones
alter table public.marketplace_tasks
  add column if not exists employer_id uuid references public.employers(id) on delete set null,
  add column if not exists budget_amount numeric(14,2),
  add column if not exists currency text not null default 'ETB',
  add column if not exists deadline timestamptz,
  add column if not exists status text not null default 'open',
  add column if not exists skills_required text[] not null default '{}';

create table if not exists public.freelance_contracts (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.marketplace_tasks(id) on delete cascade,
  employer_id uuid references public.employers(id) on delete set null,
  freelancer_id uuid not null references public.profiles(id) on delete cascade,
  agreed_amount numeric(14,2) not null,
  currency text not null default 'ETB',
  terms text,
  status text not null default 'active',
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  unique(task_id, freelancer_id),
  constraint freelance_contract_status_chk check (status in ('active','completed','cancelled','disputed'))
);

create table if not exists public.task_milestones (
  id uuid primary key default gen_random_uuid(),
  contract_id uuid not null references public.freelance_contracts(id) on delete cascade,
  milestone_order int not null,
  title text not null,
  description text,
  amount numeric(14,2) not null default 0,
  due_at timestamptz,
  status text not null default 'pending',
  submitted_at timestamptz,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  unique(contract_id, milestone_order),
  constraint milestone_status_chk check (status in ('pending','in_progress','submitted','approved','rejected','paid'))
);

create table if not exists public.task_messages (
  id uuid primary key default gen_random_uuid(),
  contract_id uuid not null references public.freelance_contracts(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  body text not null,
  attachment_url text,
  created_at timestamptz not null default now()
);

alter table public.escrow_transactions
  add column if not exists contract_id uuid references public.freelance_contracts(id) on delete set null,
  add column if not exists amount_minor bigint,
  add column if not exists currency text not null default 'ETB',
  add column if not exists provider text,
  add column if not exists external_ref text;

-- 6) Mentorship directory and requests
create table if not exists public.mentor_profiles (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  headline text,
  expertise text[] not null default '{}',
  organization text,
  years_experience int,
  bio text,
  languages text[] not null default '{}',
  verified boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint mentor_years_experience_chk check (years_experience is null or years_experience >= 0)
);

create table if not exists public.mentor_availability (
  id uuid primary key default gen_random_uuid(),
  mentor_id uuid not null references public.mentor_profiles(user_id) on delete cascade,
  weekday smallint not null,
  start_time time not null,
  end_time time not null,
  timezone text not null default 'Africa/Addis_Ababa',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint mentor_availability_weekday_chk check (weekday between 0 and 6),
  constraint mentor_availability_time_chk check (end_time > start_time)
);

create table if not exists public.mentorship_requests (
  id uuid primary key default gen_random_uuid(),
  mentor_id uuid not null references public.mentor_profiles(user_id) on delete cascade,
  mentee_id uuid not null references public.profiles(id) on delete cascade,
  topic text not null,
  message text,
  preferred_at timestamptz,
  status text not null default 'pending',
  responded_at timestamptz,
  created_at timestamptz not null default now(),
  constraint mentorship_request_status_chk check (status in ('pending','accepted','declined','cancelled')),
  constraint mentorship_request_self_chk check (mentor_id <> mentee_id)
);

alter table public.mentorship_sessions
  add column if not exists request_id uuid references public.mentorship_requests(id) on delete set null,
  add column if not exists status text not null default 'scheduled',
  add column if not exists notes text;

-- 7) Career-specific AI coach
create table if not exists public.career_coach_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text,
  career_goal text,
  summary text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.career_coach_messages (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.career_coach_sessions(id) on delete cascade,
  role text not null,
  content text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint career_coach_role_chk check (role in ('user','assistant','system'))
);

-- 8) Notification preferences
create table if not exists public.notification_preferences (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  email_enabled boolean not null default true,
  push_enabled boolean not null default true,
  sms_enabled boolean not null default false,
  opportunity_alerts boolean not null default true,
  application_updates boolean not null default true,
  mentorship_updates boolean not null default true,
  freelance_updates boolean not null default true,
  marketing_enabled boolean not null default false,
  updated_at timestamptz not null default now()
);

-- 9) Admin moderation, audit and analytics
create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid references public.profiles(id) on delete set null,
  target_type text not null,
  target_id uuid,
  reason text not null,
  details text,
  status text not null default 'open',
  assigned_to uuid references public.profiles(id) on delete set null,
  resolution_notes text,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  constraint reports_status_chk check (status in ('open','reviewing','resolved','dismissed'))
);

create table if not exists public.admin_audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.profiles(id) on delete set null,
  action text not null,
  entity_type text,
  entity_id uuid,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.platform_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete set null,
  session_id text,
  event_name text not null,
  properties jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- Indexes for high-volume access and RLS predicates
create index if not exists profile_education_user_idx on public.profile_education(user_id);
create index if not exists profile_experience_user_idx on public.profile_experience(user_id);
create index if not exists profile_projects_user_idx on public.profile_projects(user_id);
create index if not exists profile_documents_user_idx on public.profile_documents(user_id);
create index if not exists skill_assessments_skill_idx on public.skill_assessments(skill_id);
create index if not exists assessment_questions_assessment_idx on public.assessment_questions(assessment_id, question_order);
create index if not exists assessment_attempts_user_idx on public.assessment_attempts(user_id, started_at desc);
create index if not exists assessment_attempts_assessment_idx on public.assessment_attempts(assessment_id, status);
create index if not exists assessment_responses_attempt_idx on public.assessment_responses(attempt_id);
create index if not exists proctor_audit_attempt_idx on public.proctor_audit_logs(attempt_id, audit_timestamp desc);
create index if not exists employer_members_user_idx on public.employer_members(user_id, status);
create index if not exists employer_members_employer_idx on public.employer_members(employer_id, status);
create index if not exists saved_candidates_employer_idx on public.saved_candidates(employer_id, created_at desc);
create index if not exists candidate_matches_employer_idx on public.candidate_matches(employer_id, match_score desc);
create index if not exists candidate_matches_candidate_idx on public.candidate_matches(candidate_id);
create index if not exists interviews_application_idx on public.interviews(application_id, starts_at desc);
create index if not exists freelance_contracts_freelancer_idx on public.freelance_contracts(freelancer_id, status);
create index if not exists freelance_contracts_employer_idx on public.freelance_contracts(employer_id, status);
create index if not exists task_milestones_contract_idx on public.task_milestones(contract_id, milestone_order);
create index if not exists task_messages_contract_idx on public.task_messages(contract_id, created_at);
create index if not exists mentor_availability_mentor_idx on public.mentor_availability(mentor_id, weekday);
create index if not exists mentorship_requests_mentor_idx on public.mentorship_requests(mentor_id, status);
create index if not exists mentorship_requests_mentee_idx on public.mentorship_requests(mentee_id, status);
create index if not exists career_coach_sessions_user_idx on public.career_coach_sessions(user_id, updated_at desc);
create index if not exists career_coach_messages_session_idx on public.career_coach_messages(session_id, created_at);
create index if not exists reports_status_idx on public.reports(status, created_at desc);
create index if not exists admin_audit_logs_actor_idx on public.admin_audit_logs(actor_id, created_at desc);
create index if not exists platform_events_user_idx on public.platform_events(user_id, created_at desc);
create index if not exists platform_events_name_time_idx on public.platform_events(event_name, created_at desc);
create index if not exists opportunities_skills_gin_idx on public.opportunities using gin(skills_required);
create index if not exists marketplace_tasks_skills_gin_idx on public.marketplace_tasks using gin(skills_required);

-- RLS enabled before API grants/policies are added in the next migration
alter table public.profile_education enable row level security;
alter table public.profile_experience enable row level security;
alter table public.profile_projects enable row level security;
alter table public.profile_languages enable row level security;
alter table public.profile_documents enable row level security;
alter table public.skill_assessments enable row level security;
alter table public.assessment_questions enable row level security;
alter table private.assessment_answer_keys enable row level security;
alter table public.assessment_attempts enable row level security;
alter table public.assessment_responses enable row level security;
alter table public.employer_members enable row level security;
alter table public.saved_candidates enable row level security;
alter table public.candidate_matches enable row level security;
alter table public.interviews enable row level security;
alter table public.freelance_contracts enable row level security;
alter table public.task_milestones enable row level security;
alter table public.task_messages enable row level security;
alter table public.mentor_profiles enable row level security;
alter table public.mentor_availability enable row level security;
alter table public.mentorship_requests enable row level security;
alter table public.career_coach_sessions enable row level security;
alter table public.career_coach_messages enable row level security;
alter table public.notification_preferences enable row level security;
alter table public.reports enable row level security;
alter table public.admin_audit_logs enable row level security;
alter table public.platform_events enable row level security;
;
