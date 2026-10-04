-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815165912
create table if not exists private.mela_question_replacement_targets_v18 (
  target_question_id uuid primary key references public.mela_question_bank(id) on delete cascade,
  program_key text not null references public.mela_learning_programs(program_key) on delete cascade,
  chapter_id uuid references public.mela_learning_chapters(id) on delete cascade,
  topic_id uuid references public.mela_learning_chapter_topics(id) on delete cascade,
  grade_level smallint not null,
  subject_title text not null,
  current_question_type text not null,
  desired_question_type text not null,
  access_tier text not null,
  priority integer not null,
  target_reason text not null,
  status text not null default 'queued' check (status in ('queued','generating','generated','machine_validated','educator_approved','changes_required','rejected','promoted','blocked')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
revoke all on private.mela_question_replacement_targets_v18 from public,anon,authenticated;
grant select,insert,update,delete on private.mela_question_replacement_targets_v18 to service_role;

create table if not exists private.mela_question_generation_candidates_v18 (
  id uuid primary key default gen_random_uuid(),
  target_question_id uuid not null unique references private.mela_question_replacement_targets_v18(target_question_id) on delete cascade,
  program_key text not null,
  chapter_id uuid,
  topic_id uuid,
  proposed_question_type text not null,
  prompt text not null,
  choices jsonb not null default '[]'::jsonb,
  difficulty smallint not null check (difficulty between 1 and 5),
  cognitive_level text not null check (cognitive_level in ('remember','understand','apply','analyze')),
  narration_text text,
  response_schema jsonb not null default '{}'::jsonb,
  estimated_seconds integer not null default 90 check (estimated_seconds between 15 and 900),
  accessibility_support jsonb not null default '{}'::jsonb,
  grading_kind text not null,
  correct_response jsonb not null,
  accepted_variants jsonb not null default '[]'::jsonb,
  tolerance numeric,
  rationale text not null,
  generation_model text,
  generation_batch_id uuid,
  machine_quality_score numeric not null default 0 check (machine_quality_score between 0 and 100),
  quality_checks jsonb not null default '{}'::jsonb,
  status text not null default 'generated' check (status in ('generated','machine_validated','educator_approved','changes_required','rejected','promoted')),
  generated_at timestamptz not null default now(),
  reviewed_by uuid,
  reviewed_at timestamptz,
  reviewer_note text,
  promoted_at timestamptz,
  updated_at timestamptz not null default now()
);
revoke all on private.mela_question_generation_candidates_v18 from public,anon,authenticated;
grant select,insert,update,delete on private.mela_question_generation_candidates_v18 to service_role;
;
