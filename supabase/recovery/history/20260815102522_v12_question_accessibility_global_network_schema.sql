-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815102522
alter table public.mela_question_bank drop constraint if exists mela_question_bank_question_type_check;
alter table public.mela_question_bank add constraint mela_question_bank_question_type_check check (question_type in ('single_choice','true_false','multi_select','numeric','short_answer','matching','ordering','passage_choice','scenario_choice'));
alter table public.mela_question_bank add column if not exists narration_text text;
alter table public.mela_question_bank add column if not exists response_schema jsonb not null default '{}'::jsonb;
alter table public.mela_question_bank add column if not exists estimated_seconds integer not null default 90 check (estimated_seconds between 15 and 900);
alter table public.mela_question_bank add column if not exists machine_quality_score numeric(5,2) not null default 0 check (machine_quality_score between 0 and 100);
alter table public.mela_question_bank add column if not exists quality_checks jsonb not null default '{}'::jsonb;
alter table public.mela_question_bank add column if not exists accessibility_support jsonb not null default '{}'::jsonb;

create table if not exists private.mela_question_grading_v12 (
  question_id uuid primary key references public.mela_question_bank(id) on delete cascade,
  grading_kind text not null check (grading_kind in ('single_choice','true_false','multi_select','numeric','short_answer','matching','ordering')),
  correct_response jsonb not null,
  accepted_variants jsonb not null default '[]'::jsonb,
  tolerance numeric,
  rationale text not null,
  grading_version text not null default 'v12',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
revoke all on private.mela_question_grading_v12 from public,anon,authenticated;
grant select,insert,update,delete on private.mela_question_grading_v12 to service_role;

create table if not exists public.learner_accessibility_preferences (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  narration_enabled boolean not null default false,
  narration_rate numeric(3,2) not null default 1.00 check (narration_rate between 0.50 and 2.00),
  narration_language text not null default 'en',
  screen_reader_mode boolean not null default false,
  keyboard_only boolean not null default false,
  high_contrast boolean not null default false,
  text_scale numeric(3,2) not null default 1.00 check (text_scale between 1.00 and 2.00),
  reduced_motion boolean not null default false,
  captions_enabled boolean not null default true,
  simplified_language boolean not null default false,
  extended_time_multiplier numeric(3,2) not null default 1.00 check (extended_time_multiplier between 1.00 and 3.00),
  large_targets boolean not null default false,
  color_independent_mode boolean not null default false,
  preference_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.learner_accessibility_preferences enable row level security;
drop policy if exists learner_accessibility_self_select on public.learner_accessibility_preferences;
create policy learner_accessibility_self_select on public.learner_accessibility_preferences for select to authenticated using ((select auth.uid())=user_id or private.is_admin_user());
drop policy if exists learner_accessibility_self_insert on public.learner_accessibility_preferences;
create policy learner_accessibility_self_insert on public.learner_accessibility_preferences for insert to authenticated with check ((select auth.uid())=user_id);
drop policy if exists learner_accessibility_self_update on public.learner_accessibility_preferences;
create policy learner_accessibility_self_update on public.learner_accessibility_preferences for update to authenticated using ((select auth.uid())=user_id) with check ((select auth.uid())=user_id);
grant select,insert,update on public.learner_accessibility_preferences to authenticated;
grant all on public.learner_accessibility_preferences to service_role;

create table if not exists public.content_accessibility_metadata (
  id uuid primary key default gen_random_uuid(),
  content_type text not null check (content_type in ('question','chapter','material','opportunity','scholarship','application_help')),
  content_id text not null,
  narration_text text,
  transcript text,
  alt_text text,
  easy_read_summary text,
  braille_note text,
  sign_language_available boolean not null default false,
  accessibility_review_status text not null default 'machine_ready' check (accessibility_review_status in ('machine_ready','human_reviewed','needs_review')),
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(content_type,content_id)
);
alter table public.content_accessibility_metadata enable row level security;
drop policy if exists accessibility_metadata_read on public.content_accessibility_metadata;
create policy accessibility_metadata_read on public.content_accessibility_metadata for select to authenticated using (true);
drop policy if exists accessibility_metadata_admin_write on public.content_accessibility_metadata;
create policy accessibility_metadata_admin_write on public.content_accessibility_metadata for all to authenticated using (private.is_admin_user()) with check (private.is_admin_user());
grant select on public.content_accessibility_metadata to authenticated;
grant all on public.content_accessibility_metadata to service_role;

create table if not exists public.global_opportunity_sources (
  id uuid primary key default gen_random_uuid(),
  country_code text not null,
  country_name text not null,
  region text not null,
  income_group text,
  source_type text not null check (source_type in ('government_jobs','government_education','university','college','private_jobs','scholarship','internship')),
  source_name text not null,
  ownership_type text not null check (ownership_type in ('government','public_university','private_university','private_company','nonprofit')),
  base_url text not null,
  application_url text,
  canonical_domain text not null,
  supports_external_apply boolean not null default true,
  supports_status_api boolean not null default false,
  supports_sso boolean not null default false,
  verification_status text not null default 'pending' check (verification_status in ('pending','verified','rejected','stale')),
  verification_method text,
  verified_at timestamptz,
  evidence_note text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(country_code,canonical_domain,source_type)
);
alter table public.global_opportunity_sources enable row level security;
drop policy if exists global_sources_verified_read on public.global_opportunity_sources;
create policy global_sources_verified_read on public.global_opportunity_sources for select to authenticated using (active and verification_status='verified');
drop policy if exists global_sources_admin_write on public.global_opportunity_sources;
create policy global_sources_admin_write on public.global_opportunity_sources for all to authenticated using (private.is_admin_user()) with check (private.is_admin_user());
grant select on public.global_opportunity_sources to authenticated;
grant all on public.global_opportunity_sources to service_role;

create index if not exists global_opportunity_sources_country_type_idx on public.global_opportunity_sources(country_code,source_type,verification_status) where active;
create index if not exists global_opportunity_sources_domain_idx on public.global_opportunity_sources(canonical_domain);

create table if not exists public.external_application_tracking (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  source_id uuid references public.global_opportunity_sources(id) on delete set null,
  opportunity_id uuid references public.opportunities(id) on delete set null,
  external_title text not null,
  institution_name text,
  country_code text,
  application_type text not null check (application_type in ('university','college','job','internship','scholarship','training','other')),
  external_url text not null,
  external_reference text,
  status text not null default 'saved' check (status in ('saved','preparing','submitted','assessment','interview','offer','accepted','rejected','withdrawn','closed')),
  applied_at timestamptz,
  next_action_at timestamptz,
  last_checked_at timestamptz,
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.external_application_tracking enable row level security;
drop policy if exists external_app_self_read on public.external_application_tracking;
create policy external_app_self_read on public.external_application_tracking for select to authenticated using ((select auth.uid())=user_id or private.is_admin_user());
drop policy if exists external_app_self_insert on public.external_application_tracking;
create policy external_app_self_insert on public.external_application_tracking for insert to authenticated with check ((select auth.uid())=user_id);
drop policy if exists external_app_self_update on public.external_application_tracking;
create policy external_app_self_update on public.external_application_tracking for update to authenticated using ((select auth.uid())=user_id) with check ((select auth.uid())=user_id);
drop policy if exists external_app_self_delete on public.external_application_tracking;
create policy external_app_self_delete on public.external_application_tracking for delete to authenticated using ((select auth.uid())=user_id);
grant select,insert,update,delete on public.external_application_tracking to authenticated;
grant all on public.external_application_tracking to service_role;
create index if not exists external_application_tracking_user_status_idx on public.external_application_tracking(user_id,status,updated_at desc);
create index if not exists external_application_tracking_source_idx on public.external_application_tracking(source_id) where source_id is not null;

create table if not exists public.external_application_events (
  id bigserial primary key,
  application_id uuid not null references public.external_application_tracking(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  event_type text not null check (event_type in ('created','status_changed','note_added','deadline_added','reference_added','external_check','document_update')),
  old_status text,
  new_status text,
  note text,
  created_at timestamptz not null default now()
);
alter table public.external_application_events enable row level security;
drop policy if exists external_app_event_self_read on public.external_application_events;
create policy external_app_event_self_read on public.external_application_events for select to authenticated using ((select auth.uid())=user_id or private.is_admin_user());
revoke insert,update,delete on public.external_application_events from anon,authenticated;
grant select on public.external_application_events to authenticated;
grant all on public.external_application_events to service_role;
create index if not exists external_application_events_app_created_idx on public.external_application_events(application_id,created_at desc);

insert into public.platform_feature_flags(feature_key,label,description,enabled,maintenance_message,config)
values
 ('accessibility_center','Accessibility Center','Narration and functional accessibility preferences for learners.',true,null,'{}'::jsonb),
 ('global_opportunity_network','Global Opportunity Network','Verified external university, college, job and scholarship sources with Mela-side application tracking.',true,null,'{"external_status_sync":"manual_unless_api_verified"}'::jsonb)
on conflict(feature_key) do update set label=excluded.label,description=excluded.description,config=excluded.config,updated_at=now();
;
