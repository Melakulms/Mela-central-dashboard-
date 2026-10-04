-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812200832
-- Mela talent & opportunity backend alignment
-- Non-destructive: preserves existing Mela tables/data while aligning overlapping tables.

create extension if not exists "uuid-ossp" with schema extensions;

-- Enums (Postgres CREATE TYPE has no IF NOT EXISTS form, so use guarded DO blocks)
do $$
begin
  if not exists (
    select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public' and t.typname = 'launch_category'
  ) then
    create type public.launch_category as enum (
      'Business & Finance',
      'Technology',
      'Health & Sciences',
      'Agriculture & Environment',
      'Education & Social Sciences',
      'Skilled Trades',
      'Creative & Media',
      'Manufacturing & Logistics'
    );
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public' and t.typname = 'opportunity_type'
  ) then
    create type public.opportunity_type as enum (
      'jobs', 'internships', 'scholarships', 'challenges', 'freelance'
    );
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public' and t.typname = 'user_role'
  ) then
    create type public.user_role as enum ('student', 'employer', 'mentor', 'admin');
  end if;
end $$;

-- 2. Profiles: extend existing table rather than replacing it.
alter table public.profiles
  add column if not exists email text,
  add column if not exists phone_number text,
  add column if not exists role public.user_role default 'student',
  add column if not exists university text,
  add column if not exists major text,
  add column if not exists graduation_year int,
  add column if not exists gpa numeric(3,2),
  add column if not exists preferred_language text default 'English',
  add column if not exists bio text,
  add column if not exists verified_passport_badge_count int default 0;

-- Backfill identity fields from auth where possible; .invalid is a reserved non-deliverable domain.
update public.profiles p
set email = coalesce(u.email, p.id::text || '@mela.invalid')
from auth.users u
where p.id = u.id and p.email is null;

update public.profiles
set email = id::text || '@mela.invalid'
where email is null;

alter table public.profiles
  alter column email set not null,
  alter column role set default 'student',
  alter column role set not null,
  alter column preferred_language set default 'English',
  alter column verified_passport_badge_count set default 0;

create unique index if not exists profiles_email_key on public.profiles(email);
create index if not exists profiles_role_idx on public.profiles(role);
create index if not exists profiles_university_idx on public.profiles(university);
create index if not exists profiles_major_idx on public.profiles(major);

-- Repair existing auth signup trigger to match the current profile schema.
create or replace function private.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, email, preferred_language)
  values (
    new.id,
    coalesce(
      nullif(new.raw_user_meta_data ->> 'full_name', ''),
      nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
      'Mela User'
    ),
    coalesce(new.email, new.id::text || '@mela.invalid'),
    coalesce(
      nullif(new.raw_user_meta_data ->> 'preferred_language', ''),
      nullif(new.raw_user_meta_data ->> 'language', ''),
      'English'
    )
  )
  on conflict (id) do update
    set full_name = excluded.full_name,
        email = excluded.email,
        preferred_language = excluded.preferred_language,
        updated_at = now();
  return new;
end;
$$;

-- Keep protected profile fields server-controlled while preserving the existing coin protection.
create or replace function private.protect_profile_security_fields()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (select auth.uid()) is not null then
    if new.role is distinct from old.role then
      raise exception 'role cannot be changed by the profile owner';
    end if;
    if new.coin_balance is distinct from old.coin_balance then
      raise exception 'coin balance cannot be changed by the profile owner';
    end if;
    if new.verified_passport_badge_count is distinct from old.verified_passport_badge_count then
      raise exception 'verified passport badge count cannot be changed by the profile owner';
    end if;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

-- 3. Skills & verified badges
create table if not exists public.verified_skills (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  skill_name text not null,
  category public.launch_category not null,
  level text not null,
  score text not null,
  verified boolean default true,
  verification_source text not null,
  issued_at timestamptz default now()
);

create index if not exists verified_skills_user_id_idx on public.verified_skills(user_id);
create index if not exists verified_skills_category_idx on public.verified_skills(category);

-- 4. Career paths & courses
create table if not exists public.career_paths (
  id uuid primary key default gen_random_uuid(),
  category public.launch_category not null,
  title text not null,
  partner_organization text not null,
  badge_title text not null,
  level_info text not null,
  description text not null,
  unlocked_opportunities text not null,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz default now()
);

create index if not exists career_paths_category_idx on public.career_paths(category);

-- 5. Path modules
create table if not exists public.path_modules (
  id uuid primary key default gen_random_uuid(),
  career_path_id uuid not null references public.career_paths(id) on delete cascade,
  module_order int not null,
  title text not null,
  lessons_count int default 1,
  is_proctored_assessment boolean default false,
  pass_score int default 70,
  unique(career_path_id, module_order)
);

create index if not exists path_modules_career_path_id_idx on public.path_modules(career_path_id);

-- 6. Student module progress
create table if not exists public.student_module_progress (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  module_id uuid not null references public.path_modules(id) on delete cascade,
  completed boolean default false,
  quiz_score int,
  proctored_passed boolean default false,
  proctored_at timestamptz,
  unique(user_id, module_id)
);

create index if not exists student_module_progress_user_id_idx on public.student_module_progress(user_id);
create index if not exists student_module_progress_module_id_idx on public.student_module_progress(module_id);

-- 7. Opportunities: extend existing empty table, preserving legacy compatibility columns.
alter table public.opportunities
  add column if not exists employer_id uuid references public.profiles(id) on delete set null,
  add column if not exists organization_name text,
  add column if not exists logo_url text,
  add column if not exists sector_category public.launch_category,
  add column if not exists opportunity_type public.opportunity_type,
  add column if not exists employment_type_label text,
  add column if not exists stipend_or_reward text,
  add column if not exists requirements text[] default '{}',
  add column if not exists verified_active boolean default true,
  add column if not exists verified_source text;

-- Compatibility mapping from the earlier Mela schema.
update public.opportunities
set employer_id = coalesce(employer_id, posted_by),
    organization_name = coalesce(organization_name, organization)
where employer_id is null or organization_name is null;

-- Requested schema requires these fields. The overlapping table was verified empty before migration.
alter table public.opportunities
  alter column organization_name set not null,
  alter column sector_category set not null,
  alter column opportunity_type set not null,
  alter column employment_type_label set not null,
  alter column location set not null,
  alter column stipend_or_reward set not null,
  alter column deadline set not null,
  alter column description set not null,
  alter column requirements set default '{}',
  alter column requirements set not null,
  alter column verified_active set default true;

create or replace function private.sync_opportunity_compat_fields()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.employer_id is null then new.employer_id := new.posted_by; end if;
  if new.posted_by is null then new.posted_by := new.employer_id; end if;
  if new.organization_name is null then new.organization_name := new.organization; end if;
  if new.organization is null then new.organization := new.organization_name; end if;
  return new;
end;
$$;

drop trigger if exists trg_sync_opportunity_compat_fields on public.opportunities;
create trigger trg_sync_opportunity_compat_fields
before insert or update on public.opportunities
for each row execute function private.sync_opportunity_compat_fields();

create index if not exists opportunities_employer_id_idx on public.opportunities(employer_id);
create index if not exists opportunities_sector_type_idx on public.opportunities(sector_category, opportunity_type);
create index if not exists opportunities_deadline_idx on public.opportunities(deadline);
create index if not exists opportunities_active_deadline_idx on public.opportunities(verified_active, deadline);

-- 8. Applications: retain legacy user_id/submitted_at and add requested names with synchronization.
alter table public.applications
  add column if not exists applicant_id uuid references public.profiles(id) on delete cascade,
  add column if not exists passport_snapshot jsonb,
  add column if not exists applied_at timestamptz default now();

update public.applications
set applicant_id = coalesce(applicant_id, user_id),
    applied_at = coalesce(applied_at, submitted_at)
where applicant_id is null or applied_at is null;

alter table public.applications
  alter column applicant_id set not null,
  alter column applied_at set default now(),
  alter column applied_at set not null;

create or replace function private.sync_application_compat_fields()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.applicant_id is null then new.applicant_id := new.user_id; end if;
  if new.user_id is null then new.user_id := new.applicant_id; end if;
  if new.applicant_id is distinct from new.user_id then
    raise exception 'applicant_id and user_id must refer to the same profile';
  end if;
  if new.applied_at is null then new.applied_at := new.submitted_at; end if;
  if new.submitted_at is null then new.submitted_at := new.applied_at; end if;
  return new;
end;
$$;

drop trigger if exists trg_sync_application_compat_fields on public.applications;
create trigger trg_sync_application_compat_fields
before insert or update on public.applications
for each row execute function private.sync_application_compat_fields();

create unique index if not exists applications_opportunity_applicant_key
  on public.applications(opportunity_id, applicant_id);
create index if not exists applications_applicant_id_idx on public.applications(applicant_id);
create index if not exists applications_opportunity_status_idx on public.applications(opportunity_id, status);

-- 9. Proctor audit logs
create table if not exists public.proctor_audit_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  assessment_title text not null,
  face_detection_confidence numeric(3,2),
  tab_switch_count int default 0,
  flagged boolean default false,
  flagged_reason text,
  audit_timestamp timestamptz default now()
);

create index if not exists proctor_audit_logs_user_time_idx
  on public.proctor_audit_logs(user_id, audit_timestamp desc);
create index if not exists proctor_audit_logs_flagged_idx
  on public.proctor_audit_logs(flagged) where flagged = true;

-- RLS on every table in the exposed public schema touched by this migration.
alter table public.profiles enable row level security;
alter table public.verified_skills enable row level security;
alter table public.career_paths enable row level security;
alter table public.path_modules enable row level security;
alter table public.student_module_progress enable row level security;
alter table public.opportunities enable row level security;
alter table public.applications enable row level security;
alter table public.proctor_audit_logs enable row level security;

-- Replace policies on overlapping tables with least-privilege policies.
drop policy if exists "profiles_self_select" on public.profiles;
drop policy if exists "profiles_self_update" on public.profiles;
drop policy if exists "Users view own profile" on public.profiles;
drop policy if exists "Users insert own profile" on public.profiles;
drop policy if exists "Users update own profile" on public.profiles;

create policy "Users view own profile"
on public.profiles for select
to authenticated
using ((select auth.uid()) = id);

create policy "Users insert own profile"
on public.profiles for insert
to authenticated
with check ((select auth.uid()) = id);

create policy "Users update own profile"
on public.profiles for update
to authenticated
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);

-- Verified skills: students see their own; authenticated employers see verified passports.
drop policy if exists "Verified skills public to employers" on public.verified_skills;
drop policy if exists "Users view own verified skills" on public.verified_skills;
drop policy if exists "Employers view verified skills" on public.verified_skills;

create policy "Users view own verified skills"
on public.verified_skills for select
to authenticated
using ((select auth.uid()) = user_id);

create policy "Employers view verified skills"
on public.verified_skills for select
to authenticated
using (
  verified = true
  and exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid()) and p.role = 'employer'::public.user_role
  )
);

-- Public catalog content.
drop policy if exists "Public career paths viewable" on public.career_paths;
drop policy if exists "Public career paths viewable" on public.path_modules;
drop policy if exists "Public modules viewable" on public.path_modules;

create policy "Public career paths viewable"
on public.career_paths for select
to anon, authenticated
using (true);

create policy "Public modules viewable"
on public.path_modules for select
to anon, authenticated
using (true);

-- Students own their learning progress.
drop policy if exists "Students manage own module progress" on public.student_module_progress;
create policy "Students manage own module progress"
on public.student_module_progress for all
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

-- Opportunities: public reads verified active listings; owners manage their own listings.
drop policy if exists "opportunities: owner manage" on public.opportunities;
drop policy if exists "opportunities: public read open" on public.opportunities;
drop policy if exists "Public opportunities viewable" on public.opportunities;
drop policy if exists "Employers manage own opportunities" on public.opportunities;

create policy "Public opportunities viewable"
on public.opportunities for select
to anon, authenticated
using (verified_active = true);

create policy "Employers manage own opportunities"
on public.opportunities for all
to authenticated
using ((select auth.uid()) = coalesce(employer_id, posted_by))
with check ((select auth.uid()) = coalesce(employer_id, posted_by));

-- Applications: applicants can submit/read only; employers can read/update applications for their listings.
drop policy if exists "applications: poster read" on public.applications;
drop policy if exists "applications: self manage" on public.applications;
drop policy if exists "Students submit applications" on public.applications;
drop policy if exists "Applicants view own applications" on public.applications;
drop policy if exists "Employers view applications to own opportunities" on public.applications;
drop policy if exists "Employers update applications to own opportunities" on public.applications;

create policy "Students submit applications"
on public.applications for insert
to authenticated
with check ((select auth.uid()) = applicant_id);

create policy "Applicants view own applications"
on public.applications for select
to authenticated
using ((select auth.uid()) = applicant_id);

create policy "Employers view applications to own opportunities"
on public.applications for select
to authenticated
using (
  exists (
    select 1 from public.opportunities o
    where o.id = opportunity_id
      and coalesce(o.employer_id, o.posted_by) = (select auth.uid())
  )
);

create policy "Employers update applications to own opportunities"
on public.applications for update
to authenticated
using (
  exists (
    select 1 from public.opportunities o
    where o.id = opportunity_id
      and coalesce(o.employer_id, o.posted_by) = (select auth.uid())
  )
)
with check (
  exists (
    select 1 from public.opportunities o
    where o.id = opportunity_id
      and coalesce(o.employer_id, o.posted_by) = (select auth.uid())
  )
);

-- Proctor logs are sensitive: users can only read their own logs; writes stay server-side.
drop policy if exists "Users view own proctor audit logs" on public.proctor_audit_logs;
create policy "Users view own proctor audit logs"
on public.proctor_audit_logs for select
to authenticated
using ((select auth.uid()) = user_id);

-- Explicit Data API grants (required for new Supabase exposure defaults).
revoke all on table public.profiles from anon, authenticated;
revoke all on table public.verified_skills from anon, authenticated;
revoke all on table public.career_paths from anon, authenticated;
revoke all on table public.path_modules from anon, authenticated;
revoke all on table public.student_module_progress from anon, authenticated;
revoke all on table public.opportunities from anon, authenticated;
revoke all on table public.applications from anon, authenticated;
revoke all on table public.proctor_audit_logs from anon, authenticated;

grant select, insert, update on table public.profiles to authenticated;
grant select on table public.verified_skills to authenticated;
grant select on table public.career_paths to anon, authenticated;
grant select on table public.path_modules to anon, authenticated;
grant select, insert, update on table public.student_module_progress to authenticated;
grant select on table public.opportunities to anon;
grant select, insert, update, delete on table public.opportunities to authenticated;
grant select, insert, update on table public.applications to authenticated;
grant select on table public.proctor_audit_logs to authenticated;

grant select, insert, update, delete on table public.profiles to service_role;
grant select, insert, update, delete on table public.verified_skills to service_role;
grant select, insert, update, delete on table public.career_paths to service_role;
grant select, insert, update, delete on table public.path_modules to service_role;
grant select, insert, update, delete on table public.student_module_progress to service_role;
grant select, insert, update, delete on table public.opportunities to service_role;
grant select, insert, update, delete on table public.applications to service_role;
grant select, insert, update, delete on table public.proctor_audit_logs to service_role;

-- Prevent direct invocation of private trigger helpers from API roles.
revoke execute on function private.handle_new_auth_user() from public, anon, authenticated;
revoke execute on function private.protect_profile_security_fields() from public, anon, authenticated;
revoke execute on function private.sync_opportunity_compat_fields() from public, anon, authenticated;
revoke execute on function private.sync_application_compat_fields() from public, anon, authenticated;

;
