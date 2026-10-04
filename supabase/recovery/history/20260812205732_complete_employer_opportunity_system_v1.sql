-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812205732
-- MELA Step 3: Employer & Opportunity system V1

-- 1) Allow admins (but never profile owners) to manage protected profile fields.
create or replace function private.protect_profile_security_fields()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_is_admin boolean := false;
begin
  if v_uid is not null then
    select exists(
      select 1 from public.profiles p
      where p.id = v_uid and p.role = 'admin'::public.user_role
    ) into v_is_admin;

    if new.role is distinct from old.role and (v_uid = old.id or not v_is_admin) then
      raise exception 'role can only be changed by an administrator';
    end if;
    if new.coin_balance is distinct from old.coin_balance and (v_uid = old.id or not v_is_admin) then
      raise exception 'coin balance can only be changed by an administrator or trusted backend';
    end if;
    if new.verified_passport_badge_count is distinct from old.verified_passport_badge_count and (v_uid = old.id or not v_is_admin) then
      raise exception 'verified passport badge count is system managed';
    end if;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

-- 2) Enrich employer profiles.
alter table public.employers
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists legal_name text,
  add column if not exists registration_number text,
  add column if not exists company_size text,
  add column if not exists founded_year integer,
  add column if not exists address_line text,
  add column if not exists city text,
  add column if not exists country text not null default 'Ethiopia',
  add column if not exists careers_url text,
  add column if not exists linkedin_url text,
  add column if not exists hiring_email text,
  add column if not exists hiring_phone text,
  add column if not exists verification_notes text;

alter table public.employers drop constraint if exists employers_verification_status_chk;
alter table public.employers add constraint employers_verification_status_chk
  check (verification_status in ('pending','under_review','verified','rejected','suspended'));
alter table public.employers drop constraint if exists employers_company_size_chk;
alter table public.employers add constraint employers_company_size_chk
  check (company_size is null or company_size in ('1-10','11-50','51-200','201-500','501-1000','1000+'));
alter table public.employers drop constraint if exists employers_founded_year_chk;
alter table public.employers add constraint employers_founded_year_chk
  check (founded_year is null or founded_year between 1800 and 2100);
create index if not exists employers_owner_id_idx on public.employers(owner_id);
create index if not exists employers_verification_idx on public.employers(verification_status, verified);

-- 3) Employer registration/onboarding requests.
create table if not exists public.employer_registration_requests (
  id uuid primary key default gen_random_uuid(),
  applicant_user_id uuid not null references public.profiles(id) on delete cascade,
  company_name text not null,
  legal_name text,
  registration_number text,
  industry text,
  sector_category public.launch_category,
  website text,
  contact_email text,
  phone_number text,
  headquarters text,
  description text,
  status text not null default 'pending' check (status in ('pending','under_review','approved','rejected','cancelled')),
  review_notes text,
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  employer_id uuid references public.employers(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists employer_registration_user_idx on public.employer_registration_requests(applicant_user_id, created_at desc);
create index if not exists employer_registration_status_idx on public.employer_registration_requests(status, created_at);

-- Only one active registration request per user.
create unique index if not exists employer_registration_one_active_idx
on public.employer_registration_requests(applicant_user_id)
where status in ('pending','under_review','approved');

-- 4) Employer verification document metadata (actual files live in Storage later).
create table if not exists public.employer_verification_documents (
  id uuid primary key default gen_random_uuid(),
  employer_id uuid not null references public.employers(id) on delete cascade,
  document_type text not null check (document_type in ('business_license','tax_document','registration_certificate','authorization_letter','other')),
  file_path text not null,
  display_name text,
  review_status text not null default 'pending' check (review_status in ('pending','accepted','rejected')),
  review_notes text,
  uploaded_by uuid not null references public.profiles(id) on delete restrict,
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists employer_verification_docs_employer_idx on public.employer_verification_documents(employer_id, created_at desc);

-- 5) Correct opportunities.employer_id: it now references the company record, not a profile.
alter table public.opportunities drop constraint if exists opportunities_employer_id_fkey;
alter table public.opportunities
  add constraint opportunities_employer_id_fkey foreign key (employer_id)
  references public.employers(id) on delete set null;

alter table public.opportunities
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists summary text,
  add column if not exists responsibilities text[] not null default '{}',
  add column if not exists benefits text[] not null default '{}',
  add column if not exists openings_count integer not null default 1,
  add column if not exists work_arrangement text not null default 'onsite',
  add column if not exists application_method text not null default 'mela',
  add column if not exists application_instructions text,
  add column if not exists start_date date,
  add column if not exists published_at timestamptz,
  add column if not exists screening_enabled boolean not null default false;

alter table public.opportunities drop constraint if exists opportunities_status_chk;
alter table public.opportunities add constraint opportunities_status_chk
  check (status in ('draft','pending_review','open','paused','closed','filled','archived'));
alter table public.opportunities drop constraint if exists opportunities_work_arrangement_chk;
alter table public.opportunities add constraint opportunities_work_arrangement_chk
  check (work_arrangement in ('onsite','remote','hybrid'));
alter table public.opportunities drop constraint if exists opportunities_application_method_chk;
alter table public.opportunities add constraint opportunities_application_method_chk
  check (application_method in ('mela','external','both'));
alter table public.opportunities drop constraint if exists opportunities_openings_count_chk;
alter table public.opportunities add constraint opportunities_openings_count_chk check (openings_count > 0);
alter table public.opportunities drop constraint if exists opportunities_salary_range_chk;
alter table public.opportunities add constraint opportunities_salary_range_chk
  check (salary_min is null or salary_max is null or salary_max >= salary_min);
create index if not exists opportunities_employer_company_idx on public.opportunities(employer_id, status, deadline);
create index if not exists opportunities_status_deadline_idx on public.opportunities(status, deadline);

-- 6) Screening questions attached to an opportunity.
create table if not exists public.opportunity_screening_questions (
  id uuid primary key default gen_random_uuid(),
  opportunity_id uuid not null references public.opportunities(id) on delete cascade,
  question_order integer not null,
  prompt text not null,
  question_type text not null default 'text' check (question_type in ('text','yes_no','single_choice','number')),
  choices jsonb not null default '[]'::jsonb,
  required boolean not null default true,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (opportunity_id, question_order)
);
create index if not exists opportunity_screening_opportunity_idx on public.opportunity_screening_questions(opportunity_id, question_order);

-- 7) Employer-configurable matching rules.
create table if not exists public.opportunity_matching_configs (
  opportunity_id uuid primary key references public.opportunities(id) on delete cascade,
  min_match_score numeric not null default 60 check (min_match_score between 0 and 100),
  skills_weight numeric not null default 50 check (skills_weight between 0 and 100),
  education_weight numeric not null default 15 check (education_weight between 0 and 100),
  experience_weight numeric not null default 20 check (experience_weight between 0 and 100),
  verified_skills_weight numeric not null default 15 check (verified_skills_weight between 0 and 100),
  must_have_skills text[] not null default '{}',
  preferred_universities text[] not null default '{}',
  preferred_majors text[] not null default '{}',
  minimum_gpa numeric,
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now(),
  check (skills_weight + education_weight + experience_weight + verified_skills_weight = 100),
  check (minimum_gpa is null or minimum_gpa between 0 and 4)
);

-- 8) Complete application pipeline fields.
alter table public.applications
  add column if not exists screening_answers jsonb not null default '{}'::jsonb,
  add column if not exists resume_document_id uuid references public.profile_documents(id) on delete set null,
  add column if not exists withdrawn_at timestamptz;

alter table public.applications drop constraint if exists applications_status_chk;
alter table public.applications add constraint applications_status_chk
  check (status in ('submitted','reviewing','shortlisted','interview','offered','hired','rejected','withdrawn'));
create index if not exists applications_reviewer_idx on public.applications(reviewer_id);

-- Application status history is immutable to clients.
create table if not exists public.application_status_history (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references public.applications(id) on delete cascade,
  old_status text,
  new_status text not null,
  changed_by uuid references public.profiles(id) on delete set null,
  note text,
  changed_at timestamptz not null default now()
);
create index if not exists application_status_history_app_idx on public.application_status_history(application_id, changed_at);

-- Private recruiter notes; applicants cannot read these.
create table if not exists public.application_notes (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references public.applications(id) on delete cascade,
  employer_id uuid not null references public.employers(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete restrict,
  note text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists application_notes_application_idx on public.application_notes(application_id, created_at desc);
create index if not exists application_notes_employer_idx on public.application_notes(employer_id, created_at desc);

-- 9) Candidate interview response is separated from employer-managed schedule fields.
create table if not exists public.interview_candidate_responses (
  interview_id uuid primary key references public.interviews(id) on delete cascade,
  candidate_id uuid not null references public.profiles(id) on delete cascade,
  response_status text not null default 'pending' check (response_status in ('pending','accepted','declined','reschedule_requested')),
  note text,
  proposed_times jsonb not null default '[]'::jsonb,
  responded_at timestamptz,
  updated_at timestamptz not null default now()
);
create index if not exists interview_candidate_response_candidate_idx on public.interview_candidate_responses(candidate_id, updated_at desc);

-- 10) Platform-owned editable opportunity templates (not live vacancies).
create table if not exists public.opportunity_templates (
  id uuid primary key default gen_random_uuid(),
  template_key text not null unique,
  sector_category public.launch_category not null,
  opportunity_type public.opportunity_type not null,
  title text not null,
  summary text not null,
  description text not null,
  employment_type_label text not null,
  work_arrangement text not null default 'onsite' check (work_arrangement in ('onsite','remote','hybrid')),
  suggested_requirements text[] not null default '{}',
  suggested_skills text[] not null default '{}',
  suggested_responsibilities text[] not null default '{}',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 11) Triggers/functions.
create or replace function private.set_generic_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- Protect employer verification fields from non-admin browser users.
create or replace function private.protect_employer_verification_fields()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_admin boolean := false;
begin
  if v_uid is not null then
    select exists(select 1 from public.profiles p where p.id=v_uid and p.role='admin'::public.user_role) into v_admin;
    if not v_admin and (
      new.verified is distinct from old.verified or
      new.verification_status is distinct from old.verification_status or
      new.verified_at is distinct from old.verified_at or
      new.verification_notes is distinct from old.verification_notes
    ) then
      raise exception 'employer verification fields are admin managed';
    end if;
  end if;
  new.updated_at := now();
  return new;
end;
$$;
drop trigger if exists trg_protect_employer_verification on public.employers;
create trigger trg_protect_employer_verification before update on public.employers
for each row execute function private.protect_employer_verification_fields();

-- Protect registration review fields and process approvals server-side.
create or replace function private.process_employer_registration_request()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_admin boolean := false;
  v_employer_id uuid;
begin
  if v_uid is not null then
    select exists(select 1 from public.profiles p where p.id=v_uid and p.role='admin'::public.user_role) into v_admin;
  end if;

  if tg_op='UPDATE' and not v_admin and v_uid is not null then
    if new.status is distinct from old.status or
       new.review_notes is distinct from old.review_notes or
       new.reviewed_by is distinct from old.reviewed_by or
       new.reviewed_at is distinct from old.reviewed_at or
       new.employer_id is distinct from old.employer_id then
      raise exception 'review fields are admin managed';
    end if;
    if old.status not in ('pending','under_review') then
      raise exception 'request can no longer be edited';
    end if;
  end if;

  new.updated_at := now();

  if tg_op='UPDATE' and new.status in ('approved','rejected') and new.status is distinct from old.status then
    new.reviewed_by := v_uid;
    new.reviewed_at := now();
  end if;

  if tg_op='UPDATE' and new.status='approved' and old.status is distinct from 'approved' then
    update public.profiles
       set role='employer'::public.user_role
     where id=new.applicant_user_id;

    if new.employer_id is null then
      insert into public.employers(
        owner_id, company_name, legal_name, registration_number, industry,
        sector_category, website, contact_email, phone_number, headquarters,
        description, verified, verification_status
      ) values (
        new.applicant_user_id, new.company_name, new.legal_name, new.registration_number, new.industry,
        new.sector_category, new.website, new.contact_email, new.phone_number, new.headquarters,
        new.description, false, 'pending'
      ) returning id into v_employer_id;
      new.employer_id := v_employer_id;
    end if;
  end if;
  return new;
end;
$$;
revoke all on function private.process_employer_registration_request() from public;
drop trigger if exists trg_process_employer_registration on public.employer_registration_requests;
create trigger trg_process_employer_registration
before update on public.employer_registration_requests
for each row execute function private.process_employer_registration_request();

-- Review fields on verification documents are admin-managed.
create or replace function private.protect_employer_document_review()
returns trigger language plpgsql set search_path='' as $$
declare
  v_uid uuid := (select auth.uid());
  v_admin boolean := false;
begin
  if v_uid is not null then
    select exists(select 1 from public.profiles p where p.id=v_uid and p.role='admin'::public.user_role) into v_admin;
    if not v_admin and tg_op='UPDATE' and (
      new.review_status is distinct from old.review_status or
      new.review_notes is distinct from old.review_notes or
      new.reviewed_by is distinct from old.reviewed_by or
      new.reviewed_at is distinct from old.reviewed_at or
      new.employer_id is distinct from old.employer_id or
      new.uploaded_by is distinct from old.uploaded_by
    ) then raise exception 'document review fields are admin managed'; end if;
  end if;
  if tg_op='UPDATE' and new.review_status is distinct from old.review_status and v_admin then
    new.reviewed_by := v_uid;
    new.reviewed_at := now();
  end if;
  new.updated_at := now();
  return new;
end;
$$;
drop trigger if exists trg_protect_employer_document_review on public.employer_verification_documents;
create trigger trg_protect_employer_document_review before update on public.employer_verification_documents
for each row execute function private.protect_employer_document_review();

-- Sync opportunity company metadata and publication state.
create or replace function private.prepare_opportunity()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_company public.employers%rowtype;
begin
  new.updated_at := now();
  if new.posted_by is null then new.posted_by := (select auth.uid()); end if;

  if new.employer_id is not null then
    select * into v_company from public.employers where id=new.employer_id;
    if not found then raise exception 'employer not found'; end if;
    new.organization_name := v_company.company_name;
    new.organization := v_company.company_name;
    if new.logo_url is null then new.logo_url := v_company.logo_url; end if;
    if new.sector_category is null then new.sector_category := v_company.sector_category; end if;
    new.verified_active := (
      new.status='open' and new.deadline >= current_date and
      v_company.verified = true and v_company.verification_status='verified'
    );
  else
    new.verified_active := false;
  end if;

  if new.status='open' and (tg_op='INSERT' or old.status is distinct from 'open') then
    new.published_at := coalesce(new.published_at, now());
  end if;
  return new;
end;
$$;
drop trigger if exists trg_prepare_opportunity on public.opportunities;
create trigger trg_prepare_opportunity before insert or update on public.opportunities
for each row execute function private.prepare_opportunity();

-- Automatically create default matching config for every opportunity.
create or replace function private.create_default_matching_config()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  insert into public.opportunity_matching_configs(opportunity_id, updated_by)
  values (new.id, new.posted_by)
  on conflict (opportunity_id) do nothing;
  return new;
end;
$$;
revoke all on function private.create_default_matching_config() from public;
drop trigger if exists trg_create_default_matching_config on public.opportunities;
create trigger trg_create_default_matching_config after insert on public.opportunities
for each row execute function private.create_default_matching_config();

-- Track application pipeline changes and notify the applicant.
create or replace function private.track_application_status()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if tg_op='INSERT' then
    insert into public.application_status_history(application_id, old_status, new_status, changed_by)
    values(new.id, null, new.status, v_uid);
    return new;
  end if;

  if new.status is distinct from old.status then
    insert into public.application_status_history(application_id, old_status, new_status, changed_by)
    values(new.id, old.status, new.status, v_uid);

    if new.status='withdrawn' then
      new.withdrawn_at := now();
    elsif new.status in ('reviewing','shortlisted','interview','offered','hired','rejected') then
      new.reviewer_id := v_uid;
      new.reviewed_at := now();
      insert into public.notifications(user_id, title, body, ref_table, ref_id)
      values(new.applicant_id, 'Application update', 'Your application status changed to ' || new.status || '.', 'applications', new.id);
    end if;
  end if;
  new.updated_at := now();
  return new;
end;
$$;
revoke all on function private.track_application_status() from public;
drop trigger if exists trg_track_application_status_insert on public.applications;
drop trigger if exists trg_track_application_status_update on public.applications;
create trigger trg_track_application_status_insert after insert on public.applications
for each row execute function private.track_application_status();
create trigger trg_track_application_status_update before update on public.applications
for each row execute function private.track_application_status();

-- Standard updated_at triggers.
do $$
declare t text;
begin
  foreach t in array array['opportunity_screening_questions','opportunity_matching_configs','application_notes','interview_candidate_responses','opportunity_templates'] loop
    execute format('drop trigger if exists trg_%I_updated_at on public.%I', t, t);
    execute format('create trigger trg_%I_updated_at before update on public.%I for each row execute function private.set_generic_updated_at()', t, t);
  end loop;
end $$;

-- 12) RLS.
alter table public.employers enable row level security;
alter table public.employer_members enable row level security;
alter table public.employer_registration_requests enable row level security;
alter table public.employer_verification_documents enable row level security;
alter table public.opportunities enable row level security;
alter table public.opportunity_screening_questions enable row level security;
alter table public.opportunity_matching_configs enable row level security;
alter table public.applications enable row level security;
alter table public.application_status_history enable row level security;
alter table public.application_notes enable row level security;
alter table public.candidate_matches enable row level security;
alter table public.saved_candidates enable row level security;
alter table public.interviews enable row level security;
alter table public.interview_candidate_responses enable row level security;
alter table public.opportunity_templates enable row level security;

-- Replace employer policies.
drop policy if exists "employers: owner manage" on public.employers;
drop policy if exists "employers: public read verified" on public.employers;
drop policy if exists "Employers readable" on public.employers;
drop policy if exists "Employer owner creates company" on public.employers;
drop policy if exists "Employer owner updates company" on public.employers;
create policy "Employers readable" on public.employers for select to anon, authenticated
using (
  verified=true or owner_id=(select auth.uid()) or
  exists(select 1 from public.employer_members m where m.employer_id=employers.id and m.user_id=(select auth.uid()) and m.status='active') or
  exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'::public.user_role)
);
create policy "Employer owner creates company" on public.employers for insert to authenticated
with check (
  owner_id=(select auth.uid()) and verified=false and verification_status='pending' and
  exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='employer'::public.user_role)
);
create policy "Employer owner updates company" on public.employers for update to authenticated
using (owner_id=(select auth.uid()) or exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'::public.user_role))
with check (owner_id=(select auth.uid()) or exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'::public.user_role));

-- Registration requests.
drop policy if exists "Registration requests readable" on public.employer_registration_requests;
drop policy if exists "Users create employer registration request" on public.employer_registration_requests;
drop policy if exists "Users edit employer registration request" on public.employer_registration_requests;
create policy "Registration requests readable" on public.employer_registration_requests for select to authenticated
using (applicant_user_id=(select auth.uid()) or exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'::public.user_role));
create policy "Users create employer registration request" on public.employer_registration_requests for insert to authenticated
with check (applicant_user_id=(select auth.uid()) and status='pending' and employer_id is null and reviewed_by is null);
create policy "Users edit employer registration request" on public.employer_registration_requests for update to authenticated
using (applicant_user_id=(select auth.uid()) or exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'::public.user_role))
with check (applicant_user_id=(select auth.uid()) or exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'::public.user_role));

-- Employer verification docs.
drop policy if exists "Employer verification docs readable" on public.employer_verification_documents;
drop policy if exists "Employer owners upload verification docs" on public.employer_verification_documents;
drop policy if exists "Employer verification docs editable" on public.employer_verification_documents;
create policy "Employer verification docs readable" on public.employer_verification_documents for select to authenticated
using (
  exists(select 1 from public.employers e where e.id=employer_id and e.owner_id=(select auth.uid())) or
  exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'::public.user_role)
);
create policy "Employer owners upload verification docs" on public.employer_verification_documents for insert to authenticated
with check (
  uploaded_by=(select auth.uid()) and review_status='pending' and
  exists(select 1 from public.employers e where e.id=employer_id and e.owner_id=(select auth.uid()))
);
create policy "Employer verification docs editable" on public.employer_verification_documents for update to authenticated
using (
  exists(select 1 from public.employers e where e.id=employer_id and e.owner_id=(select auth.uid())) or
  exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'::public.user_role)
)
with check (
  exists(select 1 from public.employers e where e.id=employer_id and e.owner_id=(select auth.uid())) or
  exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'::public.user_role)
);

-- Employer team policies: owner/admin manage, member can read self.
-- Keep current policies but retarget roles cleanly.
drop policy if exists "Employer memberships readable" on public.employer_members;
drop policy if exists "Employer owners add members" on public.employer_members;
drop policy if exists "Employer owners delete members" on public.employer_members;
drop policy if exists "Employer owners update members" on public.employer_members;
create policy "Employer memberships readable" on public.employer_members for select to authenticated
using (user_id=(select auth.uid()) or exists(select 1 from public.employers e where e.id=employer_id and e.owner_id=(select auth.uid())) or exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'::public.user_role));
create policy "Employer owners add members" on public.employer_members for insert to authenticated
with check (exists(select 1 from public.employers e where e.id=employer_id and e.owner_id=(select auth.uid())) or exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'::public.user_role));
create policy "Employer owners update members" on public.employer_members for update to authenticated
using (exists(select 1 from public.employers e where e.id=employer_id and e.owner_id=(select auth.uid())) or exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'::public.user_role))
with check (exists(select 1 from public.employers e where e.id=employer_id and e.owner_id=(select auth.uid())) or exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'::public.user_role));
create policy "Employer owners delete members" on public.employer_members for delete to authenticated
using (exists(select 1 from public.employers e where e.id=employer_id and e.owner_id=(select auth.uid())) or exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'::public.user_role));

-- Opportunities now use employer company/team ownership.
drop policy if exists "Employers create opportunities" on public.opportunities;
drop policy if exists "Employers delete own opportunities" on public.opportunities;
drop policy if exists "Employers update own opportunities" on public.opportunities;
drop policy if exists "Opportunities readable" on public.opportunities;
create policy "Opportunities readable" on public.opportunities for select to anon, authenticated
using (
  (status='open' and verified_active=true and deadline>=current_date) or
  exists(select 1 from public.employers e where e.id=opportunities.employer_id and e.owner_id=(select auth.uid())) or
  exists(select 1 from public.employer_members m where m.employer_id=opportunities.employer_id and m.user_id=(select auth.uid()) and m.status='active') or
  exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'::public.user_role)
);
create policy "Employer teams create opportunities" on public.opportunities for insert to authenticated
with check (
  posted_by=(select auth.uid()) and employer_id is not null and (
    exists(select 1 from public.employers e where e.id=employer_id and e.owner_id=(select auth.uid())) or
    exists(select 1 from public.employer_members m where m.employer_id=opportunities.employer_id and m.user_id=(select auth.uid()) and m.status='active' and m.member_role in ('recruiter','hiring_manager','admin')) or
    exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'::public.user_role)
  )
);
create policy "Employer teams update opportunities" on public.opportunities for update to authenticated
using (
  exists(select 1 from public.employers e where e.id=employer_id and e.owner_id=(select auth.uid())) or
  exists(select 1 from public.employer_members m where m.employer_id=opportunities.employer_id and m.user_id=(select auth.uid()) and m.status='active' and m.member_role in ('recruiter','hiring_manager','admin')) or
  exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'::public.user_role)
)
with check (
  exists(select 1 from public.employers e where e.id=employer_id and e.owner_id=(select auth.uid())) or
  exists(select 1 from public.employer_members m where m.employer_id=opportunities.employer_id and m.user_id=(select auth.uid()) and m.status='active' and m.member_role in ('recruiter','hiring_manager','admin')) or
  exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'::public.user_role)
);

-- Screening questions.
create policy "Screening questions readable" on public.opportunity_screening_questions for select to anon, authenticated
using (
  exists(select 1 from public.opportunities o where o.id=opportunity_id and o.status='open' and o.verified_active=true and o.deadline>=current_date) or
  exists(select 1 from public.opportunities o join public.employers e on e.id=o.employer_id where o.id=opportunity_id and e.owner_id=(select auth.uid())) or
  exists(select 1 from public.opportunities o join public.employer_members m on m.employer_id=o.employer_id where o.id=opportunity_id and m.user_id=(select auth.uid()) and m.status='active') or
  exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'::public.user_role)
);
create policy "Employer teams manage screening questions" on public.opportunity_screening_questions for all to authenticated
using (
  exists(select 1 from public.opportunities o join public.employers e on e.id=o.employer_id where o.id=opportunity_id and e.owner_id=(select auth.uid())) or
  exists(select 1 from public.opportunities o join public.employer_members m on m.employer_id=o.employer_id where o.id=opportunity_id and m.user_id=(select auth.uid()) and m.status='active' and m.member_role in ('recruiter','hiring_manager','admin')) or
  exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'::public.user_role)
)
with check (
  exists(select 1 from public.opportunities o join public.employers e on e.id=o.employer_id where o.id=opportunity_id and e.owner_id=(select auth.uid())) or
  exists(select 1 from public.opportunities o join public.employer_members m on m.employer_id=o.employer_id where o.id=opportunity_id and m.user_id=(select auth.uid()) and m.status='active' and m.member_role in ('recruiter','hiring_manager','admin')) or
  exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'::public.user_role)
);

-- Matching configuration is editable only by the employer team/admin.
create policy "Employer teams manage matching config" on public.opportunity_matching_configs for all to authenticated
using (
  exists(select 1 from public.opportunities o join public.employers e on e.id=o.employer_id where o.id=opportunity_id and e.owner_id=(select auth.uid())) or
  exists(select 1 from public.opportunities o join public.employer_members m on m.employer_id=o.employer_id where o.id=opportunity_id and m.user_id=(select auth.uid()) and m.status='active' and m.member_role in ('recruiter','hiring_manager','admin')) or
  exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'::public.user_role)
)
with check (
  exists(select 1 from public.opportunities o join public.employers e on e.id=o.employer_id where o.id=opportunity_id and e.owner_id=(select auth.uid())) or
  exists(select 1 from public.opportunities o join public.employer_members m on m.employer_id=o.employer_id where o.id=opportunity_id and m.user_id=(select auth.uid()) and m.status='active' and m.member_role in ('recruiter','hiring_manager','admin')) or
  exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'::public.user_role)
);

-- Applications: applicant can submit/withdraw; employer team manages pipeline.
drop policy if exists "Applications readable by authorized users" on public.applications;
drop policy if exists "Employers update application status" on public.applications;
drop policy if exists "Students submit applications" on public.applications;
drop policy if exists "Students withdraw applications" on public.applications;
create policy "Applications readable by authorized users" on public.applications for select to authenticated
using (
  applicant_id=(select auth.uid()) or
  exists(select 1 from public.opportunities o join public.employers e on e.id=o.employer_id where o.id=opportunity_id and e.owner_id=(select auth.uid())) or
  exists(select 1 from public.opportunities o join public.employer_members m on m.employer_id=o.employer_id where o.id=opportunity_id and m.user_id=(select auth.uid()) and m.status='active') or
  exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'::public.user_role)
);
create policy "Students submit applications" on public.applications for insert to authenticated
with check (
  applicant_id=(select auth.uid()) and status='submitted' and
  exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='student'::public.user_role) and
  exists(select 1 from public.opportunities o where o.id=opportunity_id and o.status='open' and o.verified_active=true and o.deadline>=current_date and o.application_method in ('mela','both'))
);
create policy "Employer teams update application status" on public.applications for update to authenticated
using (
  exists(select 1 from public.opportunities o join public.employers e on e.id=o.employer_id where o.id=opportunity_id and e.owner_id=(select auth.uid())) or
  exists(select 1 from public.opportunities o join public.employer_members m on m.employer_id=o.employer_id where o.id=opportunity_id and m.user_id=(select auth.uid()) and m.status='active' and m.member_role in ('recruiter','hiring_manager','admin')) or
  exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'::public.user_role)
)
with check (status in ('submitted','reviewing','shortlisted','interview','offered','hired','rejected'));
create policy "Students withdraw applications" on public.applications for update to authenticated
using (applicant_id=(select auth.uid()) and status not in ('hired','rejected','withdrawn'))
with check (applicant_id=(select auth.uid()) and status='withdrawn');

-- Status history is readable but system-written.
create policy "Application history readable by participants" on public.application_status_history for select to authenticated
using (
  exists(select 1 from public.applications a where a.id=application_id and a.applicant_id=(select auth.uid())) or
  exists(select 1 from public.applications a join public.opportunities o on o.id=a.opportunity_id join public.employers e on e.id=o.employer_id where a.id=application_id and e.owner_id=(select auth.uid())) or
  exists(select 1 from public.applications a join public.opportunities o on o.id=a.opportunity_id join public.employer_members m on m.employer_id=o.employer_id where a.id=application_id and m.user_id=(select auth.uid()) and m.status='active') or
  exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'::public.user_role)
);

-- Recruiter notes stay private.
create policy "Employer teams manage application notes" on public.application_notes for all to authenticated
using (
  exists(select 1 from public.employers e where e.id=employer_id and e.owner_id=(select auth.uid())) or
  exists(select 1 from public.employer_members m where m.employer_id=application_notes.employer_id and m.user_id=(select auth.uid()) and m.status='active') or
  exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'::public.user_role)
)
with check (
  author_id=(select auth.uid()) and (
    exists(select 1 from public.employers e where e.id=employer_id and e.owner_id=(select auth.uid())) or
    exists(select 1 from public.employer_members m where m.employer_id=application_notes.employer_id and m.user_id=(select auth.uid()) and m.status='active') or
    exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'::public.user_role)
  )
);

-- Candidate match status only can be edited by employer team; score remains system-managed by privileges below.
drop policy if exists "Employer teams read candidate matches" on public.candidate_matches;
drop policy if exists "Employer teams update match status" on public.candidate_matches;
create policy "Employer teams read candidate matches" on public.candidate_matches for select to authenticated
using (
  exists(select 1 from public.employers e where e.id=employer_id and e.owner_id=(select auth.uid())) or
  exists(select 1 from public.employer_members m where m.employer_id=candidate_matches.employer_id and m.user_id=(select auth.uid()) and m.status='active') or
  exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'::public.user_role)
);
create policy "Employer teams update match status" on public.candidate_matches for update to authenticated
using (
  exists(select 1 from public.employers e where e.id=employer_id and e.owner_id=(select auth.uid())) or
  exists(select 1 from public.employer_members m where m.employer_id=candidate_matches.employer_id and m.user_id=(select auth.uid()) and m.status='active') or
  exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'::public.user_role)
)
with check (
  exists(select 1 from public.employers e where e.id=employer_id and e.owner_id=(select auth.uid())) or
  exists(select 1 from public.employer_members m where m.employer_id=candidate_matches.employer_id and m.user_id=(select auth.uid()) and m.status='active') or
  exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'::public.user_role)
);

-- Saved candidates remain employer-team editable.
drop policy if exists "Employer teams manage saved candidates" on public.saved_candidates;
create policy "Employer teams manage saved candidates" on public.saved_candidates for all to authenticated
using (
  exists(select 1 from public.employers e where e.id=employer_id and e.owner_id=(select auth.uid())) or
  exists(select 1 from public.employer_members m where m.employer_id=saved_candidates.employer_id and m.user_id=(select auth.uid()) and m.status='active') or
  exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'::public.user_role)
)
with check (
  saved_by=(select auth.uid()) and (
    exists(select 1 from public.employers e where e.id=employer_id and e.owner_id=(select auth.uid())) or
    exists(select 1 from public.employer_members m where m.employer_id=saved_candidates.employer_id and m.user_id=(select auth.uid()) and m.status='active') or
    exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'::public.user_role)
  )
);

-- Rewrite interview policies against company/team ownership.
drop policy if exists "Employer teams create interviews" on public.interviews;
drop policy if exists "Employer teams delete interviews" on public.interviews;
drop policy if exists "Employer teams update interviews" on public.interviews;
drop policy if exists "Interviews readable by participants" on public.interviews;
create policy "Interviews readable by participants" on public.interviews for select to authenticated
using (
  exists(select 1 from public.applications a where a.id=application_id and a.applicant_id=(select auth.uid())) or
  exists(select 1 from public.applications a join public.opportunities o on o.id=a.opportunity_id join public.employers e on e.id=o.employer_id where a.id=application_id and e.owner_id=(select auth.uid())) or
  exists(select 1 from public.applications a join public.opportunities o on o.id=a.opportunity_id join public.employer_members m on m.employer_id=o.employer_id where a.id=application_id and m.user_id=(select auth.uid()) and m.status='active') or
  exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'::public.user_role)
);
create policy "Employer teams create interviews" on public.interviews for insert to authenticated
with check (
  scheduled_by=(select auth.uid()) and (
    exists(select 1 from public.applications a join public.opportunities o on o.id=a.opportunity_id join public.employers e on e.id=o.employer_id where a.id=application_id and e.owner_id=(select auth.uid())) or
    exists(select 1 from public.applications a join public.opportunities o on o.id=a.opportunity_id join public.employer_members m on m.employer_id=o.employer_id where a.id=application_id and m.user_id=(select auth.uid()) and m.status='active' and m.member_role in ('recruiter','hiring_manager','admin')) or
    exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'::public.user_role)
  )
);
create policy "Employer teams update interviews" on public.interviews for update to authenticated
using (
  exists(select 1 from public.applications a join public.opportunities o on o.id=a.opportunity_id join public.employers e on e.id=o.employer_id where a.id=application_id and e.owner_id=(select auth.uid())) or
  exists(select 1 from public.applications a join public.opportunities o on o.id=a.opportunity_id join public.employer_members m on m.employer_id=o.employer_id where a.id=application_id and m.user_id=(select auth.uid()) and m.status='active' and m.member_role in ('recruiter','hiring_manager','admin')) or
  exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'::public.user_role)
)
with check (
  exists(select 1 from public.applications a join public.opportunities o on o.id=a.opportunity_id join public.employers e on e.id=o.employer_id where a.id=application_id and e.owner_id=(select auth.uid())) or
  exists(select 1 from public.applications a join public.opportunities o on o.id=a.opportunity_id join public.employer_members m on m.employer_id=o.employer_id where a.id=application_id and m.user_id=(select auth.uid()) and m.status='active' and m.member_role in ('recruiter','hiring_manager','admin')) or
  exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'::public.user_role)
);

-- Candidate interview response.
create policy "Interview candidate response readable" on public.interview_candidate_responses for select to authenticated
using (
  candidate_id=(select auth.uid()) or
  exists(select 1 from public.interviews i join public.applications a on a.id=i.application_id join public.opportunities o on o.id=a.opportunity_id join public.employers e on e.id=o.employer_id where i.id=interview_id and e.owner_id=(select auth.uid())) or
  exists(select 1 from public.interviews i join public.applications a on a.id=i.application_id join public.opportunities o on o.id=a.opportunity_id join public.employer_members m on m.employer_id=o.employer_id where i.id=interview_id and m.user_id=(select auth.uid()) and m.status='active') or
  exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'::public.user_role)
);
create policy "Candidate manages interview response" on public.interview_candidate_responses for insert to authenticated
with check (
  candidate_id=(select auth.uid()) and exists(select 1 from public.interviews i join public.applications a on a.id=i.application_id where i.id=interview_id and a.applicant_id=(select auth.uid()))
);
create policy "Candidate updates interview response" on public.interview_candidate_responses for update to authenticated
using (candidate_id=(select auth.uid())) with check (candidate_id=(select auth.uid()));

-- Opportunity templates are public reference content; admin edits.
create policy "Opportunity templates readable" on public.opportunity_templates for select to anon, authenticated using (active=true or exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'::public.user_role));
create policy "Admins manage opportunity templates" on public.opportunity_templates for all to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'::public.user_role))
with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'::public.user_role));

-- 13) Minimal API privileges: editable where appropriate, protected system fields elsewhere.
revoke all on public.employers, public.employer_members, public.employer_registration_requests, public.employer_verification_documents,
  public.opportunities, public.opportunity_screening_questions, public.opportunity_matching_configs,
  public.applications, public.application_status_history, public.application_notes,
  public.candidate_matches, public.saved_candidates, public.interviews, public.interview_candidate_responses,
  public.opportunity_templates from anon, authenticated;

grant select on public.employers, public.opportunities, public.opportunity_screening_questions, public.opportunity_templates to anon;

grant select on public.employers to authenticated;
grant insert (owner_id, company_name, legal_name, registration_number, industry, website, description, logo_url, contact_email, phone_number, headquarters, sector_category, company_size, founded_year, address_line, city, country, careers_url, linkedin_url, hiring_email, hiring_phone)
  on public.employers to authenticated;
grant update (company_name, legal_name, registration_number, industry, website, description, logo_url, contact_email, phone_number, headquarters, sector_category, company_size, founded_year, address_line, city, country, careers_url, linkedin_url, hiring_email, hiring_phone, verified, verification_status, verified_at, verification_notes)
  on public.employers to authenticated;

grant select, insert, update, delete on public.employer_members to authenticated;
grant select, insert, update on public.employer_registration_requests to authenticated;
grant select, insert, update on public.employer_verification_documents to authenticated;

grant select, insert, update on public.opportunities to authenticated;
grant select, insert, update, delete on public.opportunity_screening_questions to authenticated;
grant select, insert, update, delete on public.opportunity_matching_configs to authenticated;

grant select on public.applications to authenticated;
grant insert (opportunity_id, applicant_id, cover_note, screening_answers, resume_document_id) on public.applications to authenticated;
grant update (status) on public.applications to authenticated;
grant select on public.application_status_history to authenticated;
grant select, insert, update, delete on public.application_notes to authenticated;

grant select on public.candidate_matches to authenticated;
grant update (status) on public.candidate_matches to authenticated;
grant select, insert, update, delete on public.saved_candidates to authenticated;

grant select, insert, update on public.interviews to authenticated;
grant select, insert, update on public.interview_candidate_responses to authenticated;
grant select, insert, update, delete on public.opportunity_templates to authenticated;

-- Allow authenticated admins to change profile role; trigger prevents self-escalation/non-admin changes.
grant update (role) on public.profiles to authenticated;

-- Service role retains full backend access.
grant all on public.employers, public.employer_members, public.employer_registration_requests, public.employer_verification_documents,
  public.opportunities, public.opportunity_screening_questions, public.opportunity_matching_configs,
  public.applications, public.application_status_history, public.application_notes,
  public.candidate_matches, public.saved_candidates, public.interviews, public.interview_candidate_responses,
  public.opportunity_templates to service_role;

-- 14) Seed eight non-live, clearly editable opportunity templates.
insert into public.opportunity_templates(template_key, sector_category, opportunity_type, title, summary, description, employment_type_label, work_arrangement, suggested_requirements, suggested_skills, suggested_responsibilities)
values
('banking-internship','Business & Finance','internships','Graduate Banking Internship','Template for an entry-level banking internship.','Use this template to create a real banking internship. Replace all example wording with the employer’s verified details before publishing.','Internship','onsite',array['Current university/TVET student or recent graduate','Strong communication and numeracy'],array['Customer Service','Excel','Financial Literacy'],array['Support branch or operations teams','Assist with customer service','Prepare basic reports']),
('technology-junior','Technology','jobs','Junior Technology Associate','Template for a junior software, data or IT role.','Use this template for an entry-level technology vacancy and tailor the stack, portfolio requirements and responsibilities.','Full-time','hybrid',array['Relevant degree, TVET qualification, portfolio or equivalent skills'],array['Digital Literacy','Programming','Data Analysis'],array['Support product or IT delivery','Document work clearly','Collaborate with technical teams']),
('health-internship','Health & Sciences','internships','Health Support Internship','Template for supervised health-support placements.','Use only for roles appropriate to the candidate’s qualification and local professional requirements.','Internship','onsite',array['Relevant health education or training','Commitment to confidentiality and safety'],array['Patient Communication','Infection Prevention','Health Data'],array['Support supervised service delivery','Maintain accurate records','Follow safety procedures']),
('agriculture-field','Agriculture & Environment','jobs','Agribusiness Field Associate','Template for agriculture, extension or agribusiness field roles.','Customize crop, livestock, value-chain, location and travel requirements before publishing.','Full-time','onsite',array['Relevant agriculture or agribusiness background','Ability to work in field settings'],array['Agribusiness Basics','Farm Records','Market Analysis'],array['Collect field information','Support producers or partners','Maintain operational records']),
('education-program','Education & Social Sciences','jobs','Program & Community Associate','Template for education, research and community-development roles.','Customize safeguarding, language, travel and project requirements before publishing.','Full-time','hybrid',array['Relevant education/social science background','Strong facilitation and writing'],array['Facilitation','Research','Community Engagement'],array['Support program delivery','Collect and organize data','Coordinate with communities and partners']),
('skilled-trades-apprentice','Skilled Trades','internships','Technical Trades Apprenticeship','Template for supervised technical apprenticeship placements.','Specify trade, safety requirements, tools, workplace and supervision before publishing.','Apprenticeship','onsite',array['Relevant TVET training or demonstrated trade interest','Commitment to workplace safety'],array['Workplace Safety','Technical Measurement','Maintenance'],array['Assist qualified technicians','Follow safety procedures','Complete supervised practical tasks']),
('creative-junior','Creative & Media','freelance','Junior Creative Project','Template for an entry-level creative or freelance assignment.','Define deliverables, usage rights, deadlines and payment terms clearly before publishing.','Project','remote',array['Portfolio or sample work','Ability to meet agreed deadlines'],array['Content Creation','Graphic Design','Digital Marketing'],array['Produce agreed creative deliverables','Revise based on feedback','Package final files correctly']),
('logistics-trainee','Manufacturing & Logistics','internships','Operations & Logistics Trainee','Template for warehouse, manufacturing and supply-chain trainee roles.','Customize shift pattern, site, safety and operational requirements before publishing.','Traineeship','onsite',array['Relevant operations/logistics education or training','Attention to detail and safety'],array['Inventory Management','Quality Basics','Supply Chain'],array['Support inventory and warehouse processes','Maintain records','Assist continuous-improvement activities'])
on conflict (template_key) do update set
  sector_category=excluded.sector_category, opportunity_type=excluded.opportunity_type, title=excluded.title,
  summary=excluded.summary, description=excluded.description, employment_type_label=excluded.employment_type_label,
  work_arrangement=excluded.work_arrangement, suggested_requirements=excluded.suggested_requirements,
  suggested_skills=excluded.suggested_skills, suggested_responsibilities=excluded.suggested_responsibilities,
  active=true, updated_at=now();
;
