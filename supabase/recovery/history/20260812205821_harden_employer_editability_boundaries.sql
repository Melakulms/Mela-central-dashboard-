-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812205821
-- MELA Step 3 hardening: explicit editable vs protected fields.

-- Support the hiring-manager role used by opportunity/interview policies.
alter table public.employer_members drop constraint if exists employer_member_role_chk;
alter table public.employer_members add constraint employer_member_role_chk
  check (member_role in ('owner','admin','hiring_manager','recruiter','viewer'));

-- Opportunities: ownership, poster identity, verification and publication timestamps are system-managed.
revoke insert, update on public.opportunities from authenticated;
grant insert (
  employer_id, title, description, location, is_remote, external_url, deadline, status,
  sector_category, opportunity_type, employment_type_label, stipend_or_reward, requirements,
  skills_required, experience_level, education_level, salary_min, salary_max, salary_currency,
  summary, responsibilities, benefits, openings_count, work_arrangement, application_method,
  application_instructions, start_date, screening_enabled
) on public.opportunities to authenticated;
grant update (
  title, description, location, is_remote, external_url, deadline, status,
  sector_category, opportunity_type, employment_type_label, stipend_or_reward, requirements,
  skills_required, experience_level, education_level, salary_min, salary_max, salary_currency,
  summary, responsibilities, benefits, openings_count, work_arrangement, application_method,
  application_instructions, start_date, screening_enabled
) on public.opportunities to authenticated;

-- Employer team membership: identity/company linkage is immutable after creation.
revoke insert, update on public.employer_members from authenticated;
grant insert (employer_id, user_id, member_role, status, joined_at) on public.employer_members to authenticated;
grant update (member_role, status, joined_at) on public.employer_members to authenticated;

-- Matching config: created automatically; employers only edit the rules.
revoke insert, update, delete on public.opportunity_matching_configs from authenticated;
grant update (
  min_match_score, skills_weight, education_weight, experience_weight,
  verified_skills_weight, must_have_skills, preferred_universities,
  preferred_majors, minimum_gpa, updated_by
) on public.opportunity_matching_configs to authenticated;

-- Recruiter notes: author/application/company references are immutable after insert.
revoke insert, update on public.application_notes from authenticated;
grant insert (application_id, employer_id, author_id, note) on public.application_notes to authenticated;
grant update (note) on public.application_notes to authenticated;

-- Saved candidates: employer/candidate/saver identity is immutable; note remains editable.
revoke insert, update on public.saved_candidates from authenticated;
grant insert (employer_id, candidate_id, saved_by, note) on public.saved_candidates to authenticated;
grant update (note) on public.saved_candidates to authenticated;

-- Interviews: employer can edit scheduling and recruiter notes, not application ownership/scheduler identity.
revoke insert, update on public.interviews from authenticated;
grant insert (application_id, scheduled_by, starts_at, ends_at, mode, meeting_url, location, status, employer_notes)
  on public.interviews to authenticated;
grant update (starts_at, ends_at, mode, meeting_url, location, status, employer_notes)
  on public.interviews to authenticated;

-- Candidate interview responses: identity linkage is immutable.
revoke insert, update on public.interview_candidate_responses from authenticated;
grant insert (interview_id, candidate_id, response_status, note, proposed_times, responded_at)
  on public.interview_candidate_responses to authenticated;
grant update (response_status, note, proposed_times, responded_at)
  on public.interview_candidate_responses to authenticated;

-- Candidate-match scoring is backend/system managed; only workflow status is editable.
revoke update on public.candidate_matches from authenticated;
grant update (status) on public.candidate_matches to authenticated;

-- If an owner edits an already-reviewed verification document, automatically put it back in review.
create or replace function private.protect_employer_document_review()
returns trigger language plpgsql set search_path='' as $$
declare
  v_uid uuid := (select auth.uid());
  v_admin boolean := false;
  v_owner boolean := false;
begin
  if v_uid is not null then
    select exists(select 1 from public.profiles p where p.id=v_uid and p.role='admin'::public.user_role) into v_admin;
    select exists(select 1 from public.employers e where e.id=old.employer_id and e.owner_id=v_uid) into v_owner;

    if not v_admin and (
      new.review_status is distinct from old.review_status or
      new.review_notes is distinct from old.review_notes or
      new.reviewed_by is distinct from old.reviewed_by or
      new.reviewed_at is distinct from old.reviewed_at or
      new.employer_id is distinct from old.employer_id or
      new.uploaded_by is distinct from old.uploaded_by
    ) then raise exception 'document review fields are admin managed'; end if;

    if v_owner and not v_admin and (
      new.document_type is distinct from old.document_type or
      new.file_path is distinct from old.file_path or
      new.display_name is distinct from old.display_name
    ) then
      new.review_status := 'pending';
      new.review_notes := null;
      new.reviewed_by := null;
      new.reviewed_at := null;
    end if;
  end if;

  if tg_op='UPDATE' and new.review_status is distinct from old.review_status and v_admin then
    new.reviewed_by := v_uid;
    new.reviewed_at := now();
  end if;
  new.updated_at := now();
  return new;
end;
$$;

-- Ensure opportunity matching config updated_by cannot be forged.
create or replace function private.protect_matching_config_audit()
returns trigger language plpgsql set search_path='' as $$
begin
  if (select auth.uid()) is not null then
    new.updated_by := (select auth.uid());
  end if;
  new.updated_at := now();
  return new;
end;
$$;
drop trigger if exists trg_protect_matching_config_audit on public.opportunity_matching_configs;
create trigger trg_protect_matching_config_audit before update on public.opportunity_matching_configs
for each row execute function private.protect_matching_config_audit();
;
