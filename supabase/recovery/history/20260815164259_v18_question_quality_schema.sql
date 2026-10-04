-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815164259
create table if not exists private.mela_question_quality_audit_v18 (
  question_id uuid primary key references public.mela_question_bank(id) on delete cascade,
  program_key text not null,
  purpose_class text not null check (purpose_class in ('subject_mastery_candidate','curriculum_navigation','generic_study_skill')),
  requires_regeneration boolean not null,
  audit_flags jsonb not null default '{}'::jsonb,
  audited_at timestamptz not null default now()
);
revoke all on private.mela_question_quality_audit_v18 from public,anon,authenticated;
grant select,insert,update,delete on private.mela_question_quality_audit_v18 to service_role;

create table if not exists private.mela_question_regeneration_queue_v18 (
  program_key text primary key references public.mela_learning_programs(program_key) on delete cascade,
  grade_level smallint not null,
  subject_title text not null,
  track_key text,
  current_mastery_count integer not null,
  target_mastery_count integer not null default 500,
  questions_needed integer not null,
  priority integer not null default 100,
  status text not null default 'queued' check (status in ('queued','generating','generated_pending_validation','ready_for_educator_review','complete','blocked')),
  generation_policy jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
revoke all on private.mela_question_regeneration_queue_v18 from public,anon,authenticated;
grant select,insert,update,delete on private.mela_question_regeneration_queue_v18 to service_role;

create table if not exists private.mela_question_review_slices_v18 (
  id bigint generated always as identity primary key,
  program_key text not null references public.mela_learning_programs(program_key) on delete cascade,
  slice_number integer not null,
  question_ids uuid[] not null,
  question_count integer not null,
  review_scope text not null default 'subject_mastery_candidate',
  status text not null default 'pending' check (status in ('pending','assigned','in_review','changes_required','approved')),
  assigned_to uuid,
  reviewed_at timestamptz,
  reviewer_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(program_key,slice_number)
);
revoke all on private.mela_question_review_slices_v18 from public,anon,authenticated;
grant select,insert,update,delete on private.mela_question_review_slices_v18 to service_role;
grant usage,select on sequence private.mela_question_review_slices_v18_id_seq to service_role;
;
