-- Phase 8 Content Studio: draft/version workflow and admin-only inventory views.

create table if not exists admin.content_drafts (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null check (entity_type in ('chapter','material','question','translation','book','program_seed')),
  target_id uuid null,
  program_key text null,
  language_code text not null default 'en' check (language_code in ('en','am','om','ti','so')),
  title text not null check (char_length(btrim(title)) between 1 and 300),
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'draft' check (status in ('draft','submitted','approved','rejected','published','archived')),
  version integer not null default 1 check (version > 0),
  created_by uuid not null,
  updated_by uuid not null,
  submitted_at timestamptz null,
  reviewed_by uuid null,
  reviewed_at timestamptz null,
  reviewer_note text null,
  published_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table admin.content_drafts enable row level security;

create table if not exists admin.content_draft_versions (
  id bigint generated always as identity primary key,
  draft_id uuid not null references admin.content_drafts(id) on delete cascade,
  version_no integer not null check (version_no > 0),
  snapshot jsonb not null,
  changed_by uuid null,
  change_kind text not null check (change_kind in ('create','update','submit','review','publish','archive')),
  created_at timestamptz not null default now(),
  unique (draft_id, version_no)
);

alter table admin.content_draft_versions enable row level security;

create index if not exists content_drafts_program_status_idx
  on admin.content_drafts(program_key, status, updated_at desc);
create index if not exists content_drafts_entity_status_idx
  on admin.content_drafts(entity_type, status, updated_at desc);
create index if not exists content_draft_versions_draft_created_idx
  on admin.content_draft_versions(draft_id, created_at desc);

create or replace function admin.prepare_content_draft_version()
returns trigger
language plpgsql
set search_path to ''
as $function$
begin
  if tg_op = 'UPDATE' then
    if old.status = 'published' and new.status not in ('published','archived') then
      raise exception 'published content drafts are immutable; create a new draft version instead';
    end if;
    new.version := old.version + 1;
    new.updated_at := now();
  end if;
  return new;
end;
$function$;

create or replace function admin.capture_content_draft_version()
returns trigger
language plpgsql
set search_path to ''
as $function$
declare
  v_kind text;
begin
  v_kind := case
    when tg_op = 'INSERT' then 'create'
    when new.status = 'submitted' and old.status is distinct from new.status then 'submit'
    when new.status in ('approved','rejected') and old.status is distinct from new.status then 'review'
    when new.status = 'published' and old.status is distinct from new.status then 'publish'
    when new.status = 'archived' and old.status is distinct from new.status then 'archive'
    else 'update'
  end;

  insert into admin.content_draft_versions(draft_id, version_no, snapshot, changed_by, change_kind)
  values (new.id, new.version, to_jsonb(new), new.updated_by, v_kind);
  return new;
end;
$function$;

drop trigger if exists trg_prepare_content_draft_version on admin.content_drafts;
create trigger trg_prepare_content_draft_version
before update on admin.content_drafts
for each row execute function admin.prepare_content_draft_version();

drop trigger if exists trg_capture_content_draft_version on admin.content_drafts;
create trigger trg_capture_content_draft_version
after insert or update on admin.content_drafts
for each row execute function admin.capture_content_draft_version();

create or replace view admin.content_program_inventory
with (security_invoker = true)
as
with chapter_counts as (
  select program_key,
         count(*)::bigint as chapter_count,
         count(*) filter (where source_verified)::bigint as source_verified_chapters,
         count(*) filter (where status='published')::bigint as published_chapters
  from public.mela_learning_chapters
  group by program_key
), question_counts as (
  select program_key,
         count(*)::bigint as question_count,
         count(*) filter (where active)::bigint as active_questions,
         count(*) filter (where validation_status='educator_verified')::bigint as educator_verified_questions
  from public.mela_question_bank
  group by program_key
)
select p.program_key,
       p.stage_key,
       p.grade_level,
       p.track_key,
       p.subject_key,
       p.subject_title,
       p.title,
       p.program_kind,
       p.official_alignment_status,
       p.active,
       coalesce(c.chapter_count,0) as chapter_count,
       coalesce(c.source_verified_chapters,0) as source_verified_chapters,
       coalesce(c.published_chapters,0) as published_chapters,
       coalesce(q.question_count,0) as question_count,
       coalesce(q.active_questions,0) as active_questions,
       coalesce(q.educator_verified_questions,0) as educator_verified_questions,
       (coalesce(c.chapter_count,0) > 0 or coalesce(q.question_count,0) > 0) as has_content
from public.mela_learning_programs p
left join chapter_counts c on c.program_key=p.program_key
left join question_counts q on q.program_key=p.program_key;

create or replace view admin.content_translation_inventory
with (security_invoker = true)
as
select 'chapter_material'::text as source,
       language_code,
       review_status,
       count(*)::bigint as item_count
from public.mela_learning_chapter_material_translations
group by language_code, review_status
union all
select 'learning_material'::text as source,
       language_code,
       review_status,
       count(*)::bigint as item_count
from public.mela_learning_material_translations
group by language_code, review_status;

create or replace view admin.content_quality_summary
with (security_invoker = true)
as
select
  (select count(*) from public.mela_learning_programs where active) as active_programs,
  (select count(*) from public.mela_learning_chapters) as chapters,
  (select count(*) from public.mela_learning_chapters where source_verified) as source_verified_chapters,
  (select count(*) from public.mela_question_bank where active) as active_questions,
  (select count(*) from public.mela_question_bank where validation_status='educator_verified') as educator_verified_questions,
  (select count(*) from admin.content_program_inventory where active and not has_content) as empty_programs,
  (select count(*) from public.mela_chapter_review_queue where status='approved') as approved_chapter_reviews,
  (select count(*) from public.mela_chapter_review_queue where status in ('pending','in_review','submitted')) as pending_chapter_reviews,
  (select count(*) from admin.content_drafts where status='draft') as draft_count,
  (select count(*) from admin.content_drafts where status='submitted') as submitted_drafts;

revoke all on admin.content_drafts from public, anon, authenticated;
revoke all on admin.content_draft_versions from public, anon, authenticated;
revoke all on admin.content_program_inventory from public, anon, authenticated;
revoke all on admin.content_translation_inventory from public, anon, authenticated;
revoke all on admin.content_quality_summary from public, anon, authenticated;

grant select, insert, update on admin.content_drafts to service_role;
grant select, insert on admin.content_draft_versions to service_role;
grant usage, select on sequence admin.content_draft_versions_id_seq to service_role;
grant select on admin.content_program_inventory to service_role;
grant select on admin.content_translation_inventory to service_role;
grant select on admin.content_quality_summary to service_role;

revoke all on function admin.prepare_content_draft_version() from public, anon, authenticated;
revoke all on function admin.capture_content_draft_version() from public, anon, authenticated;
grant execute on function admin.prepare_content_draft_version() to service_role;
grant execute on function admin.capture_content_draft_version() to service_role;
