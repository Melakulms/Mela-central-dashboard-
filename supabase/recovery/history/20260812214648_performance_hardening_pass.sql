-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812214648
-- RLS performance cleanup: initialize auth.uid once and remove duplicate permissive policies.

drop policy if exists "Employer teams update application status" on public.applications;
drop policy if exists "Students withdraw applications" on public.applications;
create policy "Applications update by authorized actors" on public.applications
for update to authenticated
using (
  (applicant_id=(select auth.uid()) and status not in ('hired','rejected','withdrawn'))
  or exists(select 1 from public.opportunities o where o.id=opportunity_id and private.has_employer_access(o.employer_id,true))
  or private.is_admin_user()
)
with check (
  (applicant_id=(select auth.uid()) and status='withdrawn')
  or ((exists(select 1 from public.opportunities o where o.id=opportunity_id and private.has_employer_access(o.employer_id,true)) or private.is_admin_user())
      and status in ('submitted','reviewing','shortlisted','interview','offered','hired','rejected'))
);

-- Legacy self policies rewritten for authenticated role and initplan-friendly auth lookup.
drop policy if exists "arena_participants: self manage" on public.arena_participants;
create policy "Arena participants self insert" on public.arena_participants for insert to authenticated with check (user_id=(select auth.uid()));
create policy "Arena participants self update" on public.arena_participants for update to authenticated using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
create policy "Arena participants self delete" on public.arena_participants for delete to authenticated using (user_id=(select auth.uid()));

drop policy if exists "challenge_participants: self manage" on public.challenge_participants;
create policy "Challenge participants self select" on public.challenge_participants for select to authenticated using (user_id=(select auth.uid()));
create policy "Challenge participants self insert" on public.challenge_participants for insert to authenticated with check (user_id=(select auth.uid()));
create policy "Challenge participants self update" on public.challenge_participants for update to authenticated using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
create policy "Challenge participants self delete" on public.challenge_participants for delete to authenticated using (user_id=(select auth.uid()));

drop policy if exists "submissions: self manage" on public.challenge_submissions;
create policy "Challenge submissions self select" on public.challenge_submissions for select to authenticated using (user_id=(select auth.uid()));
create policy "Challenge submissions self insert" on public.challenge_submissions for insert to authenticated with check (user_id=(select auth.uid()));
create policy "Challenge submissions self update" on public.challenge_submissions for update to authenticated using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
create policy "Challenge submissions self delete" on public.challenge_submissions for delete to authenticated using (user_id=(select auth.uid()));

drop policy if exists "practice_attempts: self manage" on public.practice_attempts;
create policy "Practice attempts self select" on public.practice_attempts for select to authenticated using (user_id=(select auth.uid()));
create policy "Practice attempts self insert" on public.practice_attempts for insert to authenticated with check (user_id=(select auth.uid()));
create policy "Practice attempts self update" on public.practice_attempts for update to authenticated using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
create policy "Practice attempts self delete" on public.practice_attempts for delete to authenticated using (user_id=(select auth.uid()));

drop policy if exists "coin_tx: self read" on public.coin_transactions;
create policy "Coin transactions self read" on public.coin_transactions for select to authenticated using (user_id=(select auth.uid()));

drop policy if exists "user_badges: self read" on public.user_badges;
create policy "User badges self read" on public.user_badges for select to authenticated using (user_id=(select auth.uid()));

drop policy if exists "exam_results: self insert" on public.exam_results;
drop policy if exists "exam_results: self read" on public.exam_results;
create policy "Exam results self insert" on public.exam_results for insert to authenticated with check (user_id=(select auth.uid()));
create policy "Exam results self read" on public.exam_results for select to authenticated using (user_id=(select auth.uid()));

-- Drop policies superseded by newer controlled workflow policies.
drop policy if exists "Career coach usage owner read" on public.career_coach_usage;
drop policy if exists "Escrow readable by contract participants" on public.escrow_transactions;
drop policy if exists "Marketplace submissions readable" on public.marketplace_submissions;
drop policy if exists "Students submit marketplace proposals" on public.marketplace_submissions;
drop policy if exists "Admins update proposals" on public.marketplace_submissions;
drop policy if exists "Employer teams review proposals" on public.marketplace_submissions;
drop policy if exists "Students edit or withdraw pending proposals" on public.marketplace_submissions;
drop policy if exists "Marketplace tasks public open" on public.marketplace_tasks;
drop policy if exists "Employer teams delete unassigned tasks" on public.marketplace_tasks;

-- Avoid SELECT overlap from ALL policies by splitting mutation permissions.
drop policy if exists "Employer teams manage screening questions" on public.opportunity_screening_questions;
create policy "Employer teams insert screening questions" on public.opportunity_screening_questions
for insert to authenticated with check (exists(select 1 from public.opportunities o where o.id=opportunity_id and (private.has_employer_access(o.employer_id,true) or private.is_admin_user())));
create policy "Employer teams update screening questions" on public.opportunity_screening_questions
for update to authenticated using (exists(select 1 from public.opportunities o where o.id=opportunity_id and (private.has_employer_access(o.employer_id,true) or private.is_admin_user())))
with check (exists(select 1 from public.opportunities o where o.id=opportunity_id and (private.has_employer_access(o.employer_id,true) or private.is_admin_user())));
create policy "Employer teams delete screening questions" on public.opportunity_screening_questions
for delete to authenticated using (exists(select 1 from public.opportunities o where o.id=opportunity_id and (private.has_employer_access(o.employer_id,true) or private.is_admin_user())));

drop policy if exists "Admins manage opportunity templates" on public.opportunity_templates;
create policy "Admins insert opportunity templates" on public.opportunity_templates for insert to authenticated with check (private.is_admin_user());
create policy "Admins update opportunity templates" on public.opportunity_templates for update to authenticated using (private.is_admin_user()) with check (private.is_admin_user());
create policy "Admins delete opportunity templates" on public.opportunity_templates for delete to authenticated using (private.is_admin_user());

-- Remove exact duplicate indexes; retain the older canonical index names.
drop index if exists public.applications_reviewer_id_idx;
drop index if exists public.career_coach_messages_session_created_idx;
drop index if exists public.career_coach_sessions_user_updated_idx;
drop index if exists public.freelance_contracts_employer_status_idx;
drop index if exists public.marketplace_submission_task_user_unique;
drop index if exists public.mentorship_sessions_mentee_time_idx;
drop index if exists public.mentorship_sessions_mentor_time_idx;
drop index if exists public.mentorship_sessions_request_unique;

-- Cover foreign keys identified by the performance advisor.
create index if not exists ai_coach_sessions_lesson_id_idx on public.ai_coach_sessions(lesson_id);
create index if not exists ai_tutor_usage_course_id_idx on public.ai_tutor_usage(course_id);
create index if not exists ai_tutor_usage_session_id_idx on public.ai_tutor_usage(session_id);
create index if not exists application_notes_author_id_idx on public.application_notes(author_id);
create index if not exists application_status_history_changed_by_idx on public.application_status_history(changed_by);
create index if not exists applications_resume_document_id_idx on public.applications(resume_document_id);
create index if not exists arena_matches_topic_id_idx on public.arena_matches(topic_id);
create index if not exists arena_participants_user_id_idx on public.arena_participants(user_id);
create index if not exists assessment_attempts_reviewed_by_idx on public.assessment_attempts(reviewed_by);
create index if not exists career_coach_usage_session_id_idx on public.career_coach_usage(session_id);
create index if not exists career_passport_entries_skill_id_idx on public.career_passport_entries(skill_id);
create index if not exists career_passport_entries_user_id_idx on public.career_passport_entries(user_id);
create index if not exists career_passport_entries_verified_by_idx on public.career_passport_entries(verified_by);
create index if not exists challenge_participants_user_id_idx on public.challenge_participants(user_id);
create index if not exists challenge_submissions_challenge_id_idx on public.challenge_submissions(challenge_id);
create index if not exists challenge_submissions_user_id_idx on public.challenge_submissions(user_id);
create index if not exists course_enrollments_user_id_idx on public.course_enrollments(user_id);
create index if not exists courses_created_by_idx on public.courses(created_by);
create index if not exists employer_registration_requests_employer_id_idx on public.employer_registration_requests(employer_id);
create index if not exists employer_registration_requests_reviewed_by_idx on public.employer_registration_requests(reviewed_by);
create index if not exists employer_verification_documents_reviewed_by_idx on public.employer_verification_documents(reviewed_by);
create index if not exists employer_verification_documents_uploaded_by_idx on public.employer_verification_documents(uploaded_by);
create index if not exists escrow_transactions_payer_employer_id_idx on public.escrow_transactions(payer_employer_id);
create index if not exists escrow_transactions_task_id_idx on public.escrow_transactions(task_id);
create index if not exists escrow_transactions_user_id_idx on public.escrow_transactions(user_id);
create index if not exists exam_results_exam_id_idx on public.exam_results(exam_id);
create index if not exists freelance_contracts_created_by_idx on public.freelance_contracts(created_by);
create index if not exists lesson_progress_lesson_id_idx on public.lesson_progress(lesson_id);
create index if not exists marketplace_submissions_reviewed_by_idx on public.marketplace_submissions(reviewed_by);
create index if not exists marketplace_submissions_user_id_idx on public.marketplace_submissions(user_id);
create index if not exists marketplace_tasks_posted_by_idx on public.marketplace_tasks(posted_by);
create index if not exists mentor_profiles_verified_by_idx on public.mentor_profiles(verified_by);
create index if not exists opportunity_matching_configs_updated_by_idx on public.opportunity_matching_configs(updated_by);
create index if not exists payout_requests_escrow_id_idx on public.payout_requests(escrow_id);
create index if not exists practice_attempts_question_id_idx on public.practice_attempts(question_id);
create index if not exists practice_attempts_user_id_idx on public.practice_attempts(user_id);
create index if not exists practice_questions_topic_id_idx on public.practice_questions(topic_id);
create index if not exists proctor_reviews_reviewer_id_idx on public.proctor_reviews(reviewer_id);
create index if not exists proctored_exams_course_id_idx on public.proctored_exams(course_id);
create index if not exists proctored_exams_skill_id_idx on public.proctored_exams(skill_id);
create index if not exists profile_documents_verified_by_idx on public.profile_documents(verified_by);
create index if not exists profile_education_verified_by_idx on public.profile_education(verified_by);
create index if not exists profile_experience_verified_by_idx on public.profile_experience(verified_by);
create index if not exists profile_languages_verified_by_idx on public.profile_languages(verified_by);
create index if not exists skill_assessment_results_user_id_idx on public.skill_assessment_results(user_id);
create index if not exists study_materials_uploaded_by_idx on public.study_materials(uploaded_by);
create index if not exists task_milestones_reviewed_by_idx on public.task_milestones(reviewed_by);
create index if not exists user_badges_badge_id_idx on public.user_badges(badge_id);
;
