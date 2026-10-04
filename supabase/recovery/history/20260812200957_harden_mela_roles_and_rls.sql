-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812200957
-- Harden authorization and optimize RLS for production use.

-- Profiles are created by the Auth trigger, not by browser clients.
drop policy if exists "Users insert own profile" on public.profiles;
revoke insert, update on table public.profiles from authenticated;
grant update (
  full_name,
  phone_number,
  university,
  major,
  graduation_year,
  gpa,
  preferred_language,
  bio,
  avatar_url,
  school_name,
  region
) on table public.profiles to authenticated;

-- Verified skills: one SELECT policy avoids duplicate permissive policy evaluation.
drop policy if exists "Users view own verified skills" on public.verified_skills;
drop policy if exists "Employers view verified skills" on public.verified_skills;
drop policy if exists "Verified skills readable by authorized users" on public.verified_skills;

create policy "Verified skills readable by authorized users"
on public.verified_skills for select
to authenticated
using (
  (select auth.uid()) = user_id
  or (
    verified = true
    and (select exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid())
        and p.role = 'employer'::public.user_role
    ))
  )
  or (select exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and p.role = 'admin'::public.user_role
  ))
);

-- Opportunities: separate CRUD policies and require employer/admin role for writes.
drop policy if exists "Public opportunities viewable" on public.opportunities;
drop policy if exists "Employers manage own opportunities" on public.opportunities;
drop policy if exists "Opportunities readable" on public.opportunities;
drop policy if exists "Employers create opportunities" on public.opportunities;
drop policy if exists "Employers update own opportunities" on public.opportunities;
drop policy if exists "Employers delete own opportunities" on public.opportunities;

create policy "Opportunities readable"
on public.opportunities for select
to anon, authenticated
using (
  verified_active = true
  or (select auth.uid()) = coalesce(employer_id, posted_by)
  or (select exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and p.role = 'admin'::public.user_role
  ))
);

create policy "Employers create opportunities"
on public.opportunities for insert
to authenticated
with check (
  (
    (select auth.uid()) = coalesce(employer_id, posted_by)
    and (select exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid())
        and p.role = 'employer'::public.user_role
    ))
  )
  or (select exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and p.role = 'admin'::public.user_role
  ))
);

create policy "Employers update own opportunities"
on public.opportunities for update
to authenticated
using (
  (
    (select auth.uid()) = coalesce(employer_id, posted_by)
    and (select exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid())
        and p.role = 'employer'::public.user_role
    ))
  )
  or (select exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and p.role = 'admin'::public.user_role
  ))
)
with check (
  (
    (select auth.uid()) = coalesce(employer_id, posted_by)
    and (select exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid())
        and p.role = 'employer'::public.user_role
    ))
  )
  or (select exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and p.role = 'admin'::public.user_role
  ))
);

create policy "Employers delete own opportunities"
on public.opportunities for delete
to authenticated
using (
  (
    (select auth.uid()) = coalesce(employer_id, posted_by)
    and (select exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid())
        and p.role = 'employer'::public.user_role
    ))
  )
  or (select exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and p.role = 'admin'::public.user_role
  ))
);

-- Automatically freeze verified skills at application submission.
create or replace function private.populate_application_passport_snapshot()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'skill_id', vs.id,
        'skill_name', vs.skill_name,
        'category', vs.category,
        'level', vs.level,
        'score', vs.score,
        'verified', vs.verified,
        'verification_source', vs.verification_source,
        'issued_at', vs.issued_at
      ) order by vs.issued_at desc
    ),
    '[]'::jsonb
  )
  into new.passport_snapshot
  from public.verified_skills vs
  where vs.user_id = new.applicant_id
    and vs.verified = true;

  new.status := 'submitted';
  new.applied_at := coalesce(new.applied_at, now());
  new.submitted_at := coalesce(new.submitted_at, new.applied_at);
  return new;
end;
$$;

drop trigger if exists trg_populate_application_passport_snapshot on public.applications;
create trigger trg_populate_application_passport_snapshot
before insert on public.applications
for each row execute function private.populate_application_passport_snapshot();
revoke execute on function private.populate_application_passport_snapshot() from public, anon, authenticated;

-- Applications: students submit only; employers/admin review and update status only.
drop policy if exists "Students submit applications" on public.applications;
drop policy if exists "Applicants view own applications" on public.applications;
drop policy if exists "Employers view applications to own opportunities" on public.applications;
drop policy if exists "Employers update applications to own opportunities" on public.applications;
drop policy if exists "Applications readable by authorized users" on public.applications;
drop policy if exists "Employers update application status" on public.applications;

create policy "Students submit applications"
on public.applications for insert
to authenticated
with check (
  (select auth.uid()) = applicant_id
  and (select exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and p.role = 'student'::public.user_role
  ))
);

create policy "Applications readable by authorized users"
on public.applications for select
to authenticated
using (
  (select auth.uid()) = applicant_id
  or exists (
    select 1 from public.opportunities o
    where o.id = opportunity_id
      and coalesce(o.employer_id, o.posted_by) = (select auth.uid())
  )
  or (select exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and p.role = 'admin'::public.user_role
  ))
);

create policy "Employers update application status"
on public.applications for update
to authenticated
using (
  exists (
    select 1 from public.opportunities o
    where o.id = opportunity_id
      and coalesce(o.employer_id, o.posted_by) = (select auth.uid())
  )
  or (select exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and p.role = 'admin'::public.user_role
  ))
)
with check (
  exists (
    select 1 from public.opportunities o
    where o.id = opportunity_id
      and coalesce(o.employer_id, o.posted_by) = (select auth.uid())
  )
  or (select exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and p.role = 'admin'::public.user_role
  ))
);

revoke insert, update on table public.applications from authenticated;
grant insert (opportunity_id, applicant_id, cover_note) on table public.applications to authenticated;
grant update (status) on table public.applications to authenticated;

-- Learning progress: browser can mark completion; scores/proctored results remain server-controlled.
drop policy if exists "Students manage own module progress" on public.student_module_progress;
drop policy if exists "Students view own module progress" on public.student_module_progress;
drop policy if exists "Students create own module progress" on public.student_module_progress;
drop policy if exists "Students update own module progress" on public.student_module_progress;

create policy "Students view own module progress"
on public.student_module_progress for select
to authenticated
using ((select auth.uid()) = user_id);

create policy "Students create own module progress"
on public.student_module_progress for insert
to authenticated
with check (
  (select auth.uid()) = user_id
  and (select exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and p.role = 'student'::public.user_role
  ))
);

create policy "Students update own module progress"
on public.student_module_progress for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

revoke insert, update, delete on table public.student_module_progress from authenticated;
grant insert (user_id, module_id, completed) on table public.student_module_progress to authenticated;
grant update (completed) on table public.student_module_progress to authenticated;

-- Add missing covering indexes flagged by the advisor on tables touched by this work.
create index if not exists career_paths_created_by_idx on public.career_paths(created_by);
create index if not exists opportunities_posted_by_idx on public.opportunities(posted_by);

;
