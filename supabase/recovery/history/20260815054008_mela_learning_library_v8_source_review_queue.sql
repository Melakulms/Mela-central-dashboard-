-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815054008
create table if not exists public.mela_learning_source_requirements (
  id uuid primary key default gen_random_uuid(),
  program_key text not null references public.mela_learning_programs(program_key) on delete cascade,
  requirement_type text not null check (requirement_type in ('official_syllabus','student_textbook','teacher_guide','assessment_blueprint','past_exam','occupational_standard','institution_syllabus','department_curriculum','reference_resource')),
  title text not null,
  source_name text,
  source_url text,
  status text not null default 'pending' check (status in ('pending','located','obtained','mapped','educator_reviewed','not_applicable')),
  review_note text,
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(program_key,requirement_type)
);
create index if not exists mela_learning_source_requirements_program_idx on public.mela_learning_source_requirements(program_key,status);
alter table public.mela_learning_source_requirements enable row level security;
create policy mela_learning_source_requirements_admin_read on public.mela_learning_source_requirements for select to authenticated using (private.is_admin_user());
create policy mela_learning_source_requirements_admin_write on public.mela_learning_source_requirements for all to authenticated using (private.is_admin_user()) with check (private.is_admin_user());
grant select,insert,update,delete on public.mela_learning_source_requirements to authenticated,service_role;

insert into public.mela_learning_source_requirements(program_key,requirement_type,title,source_name,source_url,status)
select p.program_key,'official_syllabus','Official syllabus / curriculum guide — '||p.title,p.source_name,p.source_url,'located'
from public.mela_learning_programs p where p.program_kind='school_subject'
on conflict(program_key,requirement_type) do nothing;
insert into public.mela_learning_source_requirements(program_key,requirement_type,title,status)
select p.program_key,'student_textbook','Official/approved student textbook — '||p.title,'pending'
from public.mela_learning_programs p where p.program_kind='school_subject'
on conflict(program_key,requirement_type) do nothing;
insert into public.mela_learning_source_requirements(program_key,requirement_type,title,status)
select p.program_key,'teacher_guide','Official/approved teacher guide — '||p.title,'pending'
from public.mela_learning_programs p where p.program_kind='school_subject'
on conflict(program_key,requirement_type) do nothing;
insert into public.mela_learning_source_requirements(program_key,requirement_type,title,source_name,source_url,status)
select p.program_key,'assessment_blueprint','Current assessment/exam scope — '||p.title,'FDRE Ministry of Education / relevant assessment authority','https://examinfo.moe.gov.et/','located'
from public.mela_learning_programs p where p.program_kind='school_subject' and p.grade_level=12
on conflict(program_key,requirement_type) do nothing;
insert into public.mela_learning_source_requirements(program_key,requirement_type,title,status)
select p.program_key,'past_exam','Licensed/authorized past exam set — '||p.title,'pending'
from public.mela_learning_programs p where p.program_kind='school_subject' and p.grade_level=12
on conflict(program_key,requirement_type) do nothing;
insert into public.mela_learning_source_requirements(program_key,requirement_type,title,source_name,source_url,status)
select p.program_key,'occupational_standard','Current occupational standard / institutional competency map — '||p.title,p.source_name,p.source_url,'located'
from public.mela_learning_programs p where p.program_kind in ('tvet_foundation','tvet_pathway')
on conflict(program_key,requirement_type) do nothing;
insert into public.mela_learning_source_requirements(program_key,requirement_type,title,status)
select p.program_key,'institution_syllabus','Institution/program syllabus — '||p.title,'pending'
from public.mela_learning_programs p where p.program_kind in ('tvet_foundation','tvet_pathway','university_foundation','university_pathway')
on conflict(program_key,requirement_type) do nothing;
insert into public.mela_learning_source_requirements(program_key,requirement_type,title,status)
select p.program_key,'department_curriculum','Department curriculum / course specification — '||p.title,'pending'
from public.mela_learning_programs p where p.program_kind in ('university_foundation','university_pathway')
on conflict(program_key,requirement_type) do nothing;
;
