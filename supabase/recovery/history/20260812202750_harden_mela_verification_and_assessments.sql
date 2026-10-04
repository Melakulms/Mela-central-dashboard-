-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812202750
-- Prevent client users from self-verifying credentials, mentors, or employers.

create or replace function private.protect_education_verification()
returns trigger language plpgsql set search_path = '' as $$
begin
  if (select auth.uid()) is not null then
    if tg_op = 'INSERT' then
      new.verified := false;
      new.verification_source := null;
    else
      if new.verified is distinct from old.verified or new.verification_source is distinct from old.verification_source then
        raise exception 'education verification fields are server-managed';
      end if;
    end if;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_protect_education_verification on public.profile_education;
create trigger trg_protect_education_verification
before insert or update on public.profile_education
for each row execute function private.protect_education_verification();

create or replace function private.protect_experience_verification()
returns trigger language plpgsql set search_path = '' as $$
begin
  if (select auth.uid()) is not null then
    if tg_op = 'INSERT' then
      new.verified := false;
      new.verification_source := null;
    else
      if new.verified is distinct from old.verified or new.verification_source is distinct from old.verification_source then
        raise exception 'experience verification fields are server-managed';
      end if;
    end if;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_protect_experience_verification on public.profile_experience;
create trigger trg_protect_experience_verification
before insert or update on public.profile_experience
for each row execute function private.protect_experience_verification();

create or replace function private.protect_document_verification()
returns trigger language plpgsql set search_path = '' as $$
begin
  if (select auth.uid()) is not null then
    if tg_op = 'INSERT' then
      new.verified := false;
    elsif new.verified is distinct from old.verified then
      raise exception 'document verification is server-managed';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_protect_document_verification on public.profile_documents;
create trigger trg_protect_document_verification
before insert or update on public.profile_documents
for each row execute function private.protect_document_verification();

create or replace function private.protect_language_verification()
returns trigger language plpgsql set search_path = '' as $$
begin
  if (select auth.uid()) is not null then
    if tg_op = 'INSERT' then
      new.verified := false;
    elsif new.verified is distinct from old.verified then
      raise exception 'language verification is server-managed';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_protect_language_verification on public.profile_languages;
create trigger trg_protect_language_verification
before insert or update on public.profile_languages
for each row execute function private.protect_language_verification();

create or replace function private.protect_mentor_verification()
returns trigger language plpgsql set search_path = '' as $$
begin
  if (select auth.uid()) is not null then
    if tg_op = 'INSERT' then
      new.verified := false;
    elsif new.verified is distinct from old.verified then
      raise exception 'mentor verification is server-managed';
    end if;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_protect_mentor_verification on public.mentor_profiles;
create trigger trg_protect_mentor_verification
before insert or update on public.mentor_profiles
for each row execute function private.protect_mentor_verification();

create or replace function private.protect_employer_verification()
returns trigger language plpgsql set search_path = '' as $$
begin
  if (select auth.uid()) is not null then
    if tg_op = 'INSERT' then
      new.verified := false;
      new.verification_status := 'pending';
      new.verified_at := null;
    else
      if new.verified is distinct from old.verified
         or new.verification_status is distinct from old.verification_status
         or new.verified_at is distinct from old.verified_at then
        raise exception 'employer verification fields are server-managed';
      end if;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_protect_employer_verification on public.employers;
create trigger trg_protect_employer_verification
before insert or update on public.employers
for each row execute function private.protect_employer_verification();

-- Make starting an assessment enforce publication, max attempts and proctoring mode.
drop policy if exists "Students start own attempt" on public.assessment_attempts;
create policy "Students start own attempt" on public.assessment_attempts
for insert to authenticated with check (
  user_id = (select auth.uid())
  and status = 'in_progress'
  and score is null
  and passed is null
  and integrity_score is null
  and exists (
    select 1 from public.skill_assessments sa
    where sa.id = assessment_id
      and sa.status = 'published'
      and proctored = sa.is_proctored
      and attempt_no between 1 and sa.max_attempts
      and attempt_no = 1 + (
        select count(*)::int from public.assessment_attempts prev
        where prev.assessment_id = assessment_id and prev.user_id = (select auth.uid())
      )
  )
);

-- A response must belong to a question from the same assessment as its attempt.
drop policy if exists "Responses insert by attempt owner" on public.assessment_responses;
create policy "Responses insert by attempt owner" on public.assessment_responses
for insert to authenticated with check (
  exists (
    select 1
    from public.assessment_attempts a
    join public.assessment_questions q on q.assessment_id = a.assessment_id
    where a.id = attempt_id
      and q.id = question_id
      and a.user_id = (select auth.uid())
      and a.status = 'in_progress'
      and q.active = true
  )
);

drop policy if exists "Responses update by attempt owner" on public.assessment_responses;
create policy "Responses update by attempt owner" on public.assessment_responses
for update to authenticated using (
  exists (select 1 from public.assessment_attempts a where a.id = attempt_id and a.user_id = (select auth.uid()) and a.status = 'in_progress')
) with check (
  exists (
    select 1
    from public.assessment_attempts a
    join public.assessment_questions q on q.assessment_id = a.assessment_id
    where a.id = attempt_id
      and q.id = question_id
      and a.user_id = (select auth.uid())
      and a.status = 'in_progress'
      and q.active = true
  )
);

;
