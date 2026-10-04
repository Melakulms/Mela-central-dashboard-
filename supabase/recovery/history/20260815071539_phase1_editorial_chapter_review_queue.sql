-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815071539
create table if not exists public.mela_chapter_review_queue(
  id uuid primary key default gen_random_uuid(),
  chapter_id uuid not null references public.mela_learning_chapters(id) on delete cascade,
  program_key text not null references public.mela_learning_programs(program_key) on update cascade on delete cascade,
  grade_level smallint not null check(grade_level between 1 and 12),
  subject_key text not null,
  chapter_number smallint not null,
  chapter_title text not null,
  source_state text not null,
  review_type text not null default 'chapter_toc_and_content' check(review_type in ('chapter_toc_and_content','learning_outcomes','assessment_quality','local_context')),
  priority integer not null default 100,
  status text not null default 'pending' check(status in ('pending','in_progress','approved','needs_changes','blocked_source')),
  reviewer_requirement text not null,
  assigned_to uuid references public.profiles(id) on delete set null,
  assigned_at timestamptz,
  reviewed_at timestamptz,
  reviewer_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(chapter_id,review_type)
);
alter table public.mela_chapter_review_queue enable row level security;
drop policy if exists mela_chapter_review_queue_admin_read on public.mela_chapter_review_queue;
create policy mela_chapter_review_queue_admin_read on public.mela_chapter_review_queue for select to authenticated using(private.is_admin_user());
drop policy if exists mela_chapter_review_queue_admin_write on public.mela_chapter_review_queue;
create policy mela_chapter_review_queue_admin_write on public.mela_chapter_review_queue for all to authenticated using(private.is_admin_user()) with check(private.is_admin_user());
create index if not exists mela_chapter_review_queue_status_priority_idx on public.mela_chapter_review_queue(status,priority desc,grade_level,subject_key);
create index if not exists mela_chapter_review_queue_assigned_idx on public.mela_chapter_review_queue(assigned_to) where assigned_to is not null;

insert into public.mela_chapter_review_queue(chapter_id,program_key,grade_level,subject_key,chapter_number,chapter_title,source_state,priority,status,reviewer_requirement)
select c.id,p.program_key,p.grade_level,p.subject_key,c.chapter_number,c.title,c.official_alignment_status,
       ((13-p.grade_level)*10 + case when p.subject_key in ('mathematics','english','native_language','federal_working_language','environmental_science','general_science','physics','chemistry','biology') then 20 else 0 end)::int,
       'pending',
       case when p.grade_level<=6 then 'Qualified Ethiopian primary educator or subject specialist; verify exact textbook/syllabus source, age appropriateness, learning outcomes and examples.'
            else 'Qualified Ethiopian subject educator; verify exact textbook/syllabus source, chapter title/sequence, learning outcomes, assessment quality and local context.' end
from public.mela_learning_chapters c join public.mela_learning_programs p on p.program_key=c.program_key
where p.program_kind='school_subject' and p.grade_level between 1 and 12
on conflict(chapter_id,review_type) do update set
  grade_level=excluded.grade_level,subject_key=excluded.subject_key,chapter_number=excluded.chapter_number,chapter_title=excluded.chapter_title,source_state=excluded.source_state,priority=excluded.priority,reviewer_requirement=excluded.reviewer_requirement,updated_at=now();

;
