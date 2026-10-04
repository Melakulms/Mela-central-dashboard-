-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812202716
-- Secure the completed Mela schema with explicit grants and RLS.

-- Keep private answer keys private.
revoke all on schema private from anon, authenticated;
revoke all on private.assessment_answer_keys from anon, authenticated;
grant usage on schema private to service_role;
grant all on private.assessment_answer_keys to service_role;

-- Service role access to all new public tables.
grant all on public.profile_education, public.profile_experience, public.profile_projects,
  public.profile_languages, public.profile_documents, public.skill_assessments,
  public.assessment_questions, public.assessment_attempts, public.assessment_responses,
  public.employer_members, public.saved_candidates, public.candidate_matches,
  public.interviews, public.freelance_contracts, public.task_milestones,
  public.task_messages, public.mentor_profiles, public.mentor_availability,
  public.mentorship_requests, public.career_coach_sessions, public.career_coach_messages,
  public.notification_preferences, public.reports, public.admin_audit_logs,
  public.platform_events to service_role;

-- Public catalog reads.
grant select on public.skill_assessments, public.assessment_questions,
  public.mentor_profiles, public.mentor_availability to anon;

-- Authenticated access; RLS below determines which rows.
grant select, insert, update, delete on public.profile_education, public.profile_experience,
  public.profile_projects, public.profile_languages, public.profile_documents to authenticated;

grant select, insert, update, delete on public.skill_assessments, public.assessment_questions to authenticated;
grant select, insert on public.assessment_attempts to authenticated;
grant update (status, submitted_at, duration_seconds, metadata) on public.assessment_attempts to authenticated;
grant select, insert, update on public.assessment_responses to authenticated;

grant select, insert, update, delete on public.employer_members, public.saved_candidates to authenticated;
grant select on public.candidate_matches to authenticated;
grant update (status) on public.candidate_matches to authenticated;
grant select, insert, update, delete on public.interviews to authenticated;

grant select, insert, update, delete on public.freelance_contracts, public.task_milestones to authenticated;
grant select, insert on public.task_messages to authenticated;

grant select, insert, update, delete on public.mentor_profiles, public.mentor_availability,
  public.mentorship_requests to authenticated;

grant select, insert, update, delete on public.career_coach_sessions to authenticated;
grant select, insert on public.career_coach_messages to authenticated;

grant select, insert, update, delete on public.notification_preferences to authenticated;
grant select, insert, update on public.reports to authenticated;
grant select on public.admin_audit_logs to authenticated;
grant select, insert on public.platform_events to authenticated;

-- Existing profile columns added in this migration.
grant update (city, availability_status, portfolio_url, linkedin_url, github_url) on public.profiles to authenticated;

-- Helper predicates are written inline and rely only on the caller's own visible profile/membership.

-- Career Passport: owner edits; employers/admins can read public items.
create policy "Education readable by owner or employer" on public.profile_education
for select to authenticated using (
  user_id = (select auth.uid()) or
  (is_public and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role in ('employer','admin')))
);
create policy "Education insert own" on public.profile_education
for insert to authenticated with check (user_id = (select auth.uid()));
create policy "Education update own" on public.profile_education
for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "Education delete own" on public.profile_education
for delete to authenticated using (user_id = (select auth.uid()));

create policy "Experience readable by owner or employer" on public.profile_experience
for select to authenticated using (
  user_id = (select auth.uid()) or
  (is_public and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role in ('employer','admin')))
);
create policy "Experience insert own" on public.profile_experience
for insert to authenticated with check (user_id = (select auth.uid()));
create policy "Experience update own" on public.profile_experience
for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "Experience delete own" on public.profile_experience
for delete to authenticated using (user_id = (select auth.uid()));

create policy "Projects readable by owner or employer" on public.profile_projects
for select to authenticated using (
  user_id = (select auth.uid()) or
  (is_public and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role in ('employer','admin')))
);
create policy "Projects insert own" on public.profile_projects
for insert to authenticated with check (user_id = (select auth.uid()));
create policy "Projects update own" on public.profile_projects
for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "Projects delete own" on public.profile_projects
for delete to authenticated using (user_id = (select auth.uid()));

create policy "Languages readable by owner or employer" on public.profile_languages
for select to authenticated using (
  user_id = (select auth.uid()) or
  exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role in ('employer','admin'))
);
create policy "Languages insert own" on public.profile_languages
for insert to authenticated with check (user_id = (select auth.uid()));
create policy "Languages update own" on public.profile_languages
for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "Languages delete own" on public.profile_languages
for delete to authenticated using (user_id = (select auth.uid()));

create policy "Documents readable by owner or employer" on public.profile_documents
for select to authenticated using (
  user_id = (select auth.uid()) or
  (is_public and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role in ('employer','admin')))
);
create policy "Documents insert own" on public.profile_documents
for insert to authenticated with check (user_id = (select auth.uid()) and verified = false);
create policy "Documents update own" on public.profile_documents
for update to authenticated using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));
create policy "Documents delete own" on public.profile_documents
for delete to authenticated using (user_id = (select auth.uid()));

-- Assessments: published catalog public; admin manages definition.
create policy "Published assessments public" on public.skill_assessments
for select to anon, authenticated using (
  status = 'published' or exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin')
);
create policy "Admins insert assessments" on public.skill_assessments
for insert to authenticated with check (exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin'));
create policy "Admins update assessments" on public.skill_assessments
for update to authenticated using (exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin'))
with check (exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin'));
create policy "Admins delete assessments" on public.skill_assessments
for delete to authenticated using (exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin'));

create policy "Published questions public" on public.assessment_questions
for select to anon, authenticated using (
  active and exists (select 1 from public.skill_assessments a where a.id = assessment_id and a.status = 'published')
  or exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin')
);
create policy "Admins insert questions" on public.assessment_questions
for insert to authenticated with check (exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin'));
create policy "Admins update questions" on public.assessment_questions
for update to authenticated using (exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin'))
with check (exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin'));
create policy "Admins delete questions" on public.assessment_questions
for delete to authenticated using (exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin'));

create policy "Attempts readable by owner or admin" on public.assessment_attempts
for select to authenticated using (
  user_id = (select auth.uid()) or
  exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin')
);
create policy "Students start own attempt" on public.assessment_attempts
for insert to authenticated with check (
  user_id = (select auth.uid()) and status = 'in_progress' and score is null and passed is null and integrity_score is null
);
create policy "Students submit own attempt" on public.assessment_attempts
for update to authenticated using (user_id = (select auth.uid()) and status = 'in_progress')
with check (user_id = (select auth.uid()) and status in ('in_progress','submitted') and score is null and passed is null and integrity_score is null);

create policy "Responses readable by attempt owner" on public.assessment_responses
for select to authenticated using (
  exists (select 1 from public.assessment_attempts a where a.id = attempt_id and (a.user_id = (select auth.uid()) or exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin')))
);
create policy "Responses insert by attempt owner" on public.assessment_responses
for insert to authenticated with check (
  exists (select 1 from public.assessment_attempts a where a.id = attempt_id and a.user_id = (select auth.uid()) and a.status = 'in_progress')
);
create policy "Responses update by attempt owner" on public.assessment_responses
for update to authenticated using (
  exists (select 1 from public.assessment_attempts a where a.id = attempt_id and a.user_id = (select auth.uid()) and a.status = 'in_progress')
) with check (
  exists (select 1 from public.assessment_attempts a where a.id = attempt_id and a.user_id = (select auth.uid()) and a.status = 'in_progress')
);

-- Employer team membership.
create policy "Employer memberships readable" on public.employer_members
for select to authenticated using (
  user_id = (select auth.uid()) or
  exists (select 1 from public.employers e where e.id = employer_id and e.owner_id = (select auth.uid())) or
  exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin')
);
create policy "Employer owners add members" on public.employer_members
for insert to authenticated with check (
  exists (select 1 from public.employers e where e.id = employer_id and e.owner_id = (select auth.uid())) or
  exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin')
);
create policy "Employer owners update members" on public.employer_members
for update to authenticated using (
  exists (select 1 from public.employers e where e.id = employer_id and e.owner_id = (select auth.uid())) or
  exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin')
) with check (
  exists (select 1 from public.employers e where e.id = employer_id and e.owner_id = (select auth.uid())) or
  exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin')
);
create policy "Employer owners delete members" on public.employer_members
for delete to authenticated using (
  exists (select 1 from public.employers e where e.id = employer_id and e.owner_id = (select auth.uid())) or
  exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin')
);

create policy "Employer teams manage saved candidates" on public.saved_candidates
for all to authenticated using (
  exists (select 1 from public.employers e where e.id = employer_id and e.owner_id = (select auth.uid())) or
  exists (select 1 from public.employer_members m where m.employer_id = saved_candidates.employer_id and m.user_id = (select auth.uid()) and m.status = 'active') or
  exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin')
) with check (
  saved_by = (select auth.uid()) and (
    exists (select 1 from public.employers e where e.id = employer_id and e.owner_id = (select auth.uid())) or
    exists (select 1 from public.employer_members m where m.employer_id = saved_candidates.employer_id and m.user_id = (select auth.uid()) and m.status = 'active') or
    exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin')
  )
);

create policy "Employer teams read candidate matches" on public.candidate_matches
for select to authenticated using (
  exists (select 1 from public.employers e where e.id = employer_id and e.owner_id = (select auth.uid())) or
  exists (select 1 from public.employer_members m where m.employer_id = candidate_matches.employer_id and m.user_id = (select auth.uid()) and m.status = 'active') or
  exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin')
);
create policy "Employer teams update match status" on public.candidate_matches
for update to authenticated using (
  exists (select 1 from public.employers e where e.id = employer_id and e.owner_id = (select auth.uid())) or
  exists (select 1 from public.employer_members m where m.employer_id = candidate_matches.employer_id and m.user_id = (select auth.uid()) and m.status = 'active') or
  exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin')
) with check (
  exists (select 1 from public.employers e where e.id = employer_id and e.owner_id = (select auth.uid())) or
  exists (select 1 from public.employer_members m where m.employer_id = candidate_matches.employer_id and m.user_id = (select auth.uid()) and m.status = 'active') or
  exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin')
);

create policy "Interviews readable by participants" on public.interviews
for select to authenticated using (
  exists (select 1 from public.applications a where a.id = application_id and a.applicant_id = (select auth.uid())) or
  exists (select 1 from public.applications a join public.opportunities o on o.id = a.opportunity_id where a.id = application_id and (o.employer_id in (select e.id from public.employers e where e.owner_id = (select auth.uid())) or o.employer_id in (select m.employer_id from public.employer_members m where m.user_id = (select auth.uid()) and m.status = 'active'))) or
  exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin')
);
create policy "Employer teams create interviews" on public.interviews
for insert to authenticated with check (
  scheduled_by = (select auth.uid()) and exists (
    select 1 from public.applications a join public.opportunities o on o.id = a.opportunity_id
    where a.id = application_id and (o.employer_id in (select e.id from public.employers e where e.owner_id = (select auth.uid())) or o.employer_id in (select m.employer_id from public.employer_members m where m.user_id = (select auth.uid()) and m.status = 'active'))
  )
);
create policy "Employer teams update interviews" on public.interviews
for update to authenticated using (
  exists (select 1 from public.applications a join public.opportunities o on o.id = a.opportunity_id where a.id = application_id and (o.employer_id in (select e.id from public.employers e where e.owner_id = (select auth.uid())) or o.employer_id in (select m.employer_id from public.employer_members m where m.user_id = (select auth.uid()) and m.status = 'active')))
) with check (
  exists (select 1 from public.applications a join public.opportunities o on o.id = a.opportunity_id where a.id = application_id and (o.employer_id in (select e.id from public.employers e where e.owner_id = (select auth.uid())) or o.employer_id in (select m.employer_id from public.employer_members m where m.user_id = (select auth.uid()) and m.status = 'active')))
);
create policy "Employer teams delete interviews" on public.interviews
for delete to authenticated using (
  exists (select 1 from public.applications a join public.opportunities o on o.id = a.opportunity_id where a.id = application_id and (o.employer_id in (select e.id from public.employers e where e.owner_id = (select auth.uid())) or o.employer_id in (select m.employer_id from public.employer_members m where m.user_id = (select auth.uid()) and m.status = 'active')))
);

-- Freelance: participants read, employers manage contracts/milestones, participants message.
create policy "Contracts readable by participants" on public.freelance_contracts
for select to authenticated using (
  freelancer_id = (select auth.uid()) or
  exists (select 1 from public.employers e where e.id = employer_id and e.owner_id = (select auth.uid())) or
  exists (select 1 from public.employer_members m where m.employer_id = freelance_contracts.employer_id and m.user_id = (select auth.uid()) and m.status = 'active') or
  exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin')
);
create policy "Employer teams create contracts" on public.freelance_contracts
for insert to authenticated with check (
  exists (select 1 from public.employers e where e.id = employer_id and e.owner_id = (select auth.uid())) or
  exists (select 1 from public.employer_members m where m.employer_id = freelance_contracts.employer_id and m.user_id = (select auth.uid()) and m.status = 'active') or
  exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin')
);
create policy "Employer teams update contracts" on public.freelance_contracts
for update to authenticated using (
  exists (select 1 from public.employers e where e.id = employer_id and e.owner_id = (select auth.uid())) or
  exists (select 1 from public.employer_members m where m.employer_id = freelance_contracts.employer_id and m.user_id = (select auth.uid()) and m.status = 'active') or
  exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin')
) with check (
  exists (select 1 from public.employers e where e.id = employer_id and e.owner_id = (select auth.uid())) or
  exists (select 1 from public.employer_members m where m.employer_id = freelance_contracts.employer_id and m.user_id = (select auth.uid()) and m.status = 'active') or
  exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin')
);
create policy "Employer teams delete contracts" on public.freelance_contracts
for delete to authenticated using (
  exists (select 1 from public.employers e where e.id = employer_id and e.owner_id = (select auth.uid())) or
  exists (select 1 from public.employer_members m where m.employer_id = freelance_contracts.employer_id and m.user_id = (select auth.uid()) and m.status = 'active') or
  exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin')
);

create policy "Milestones readable by contract participants" on public.task_milestones
for select to authenticated using (
  exists (select 1 from public.freelance_contracts c where c.id = contract_id and (c.freelancer_id = (select auth.uid()) or exists (select 1 from public.employers e where e.id = c.employer_id and e.owner_id = (select auth.uid())) or exists (select 1 from public.employer_members m where m.employer_id = c.employer_id and m.user_id = (select auth.uid()) and m.status='active')))
  or exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role='admin')
);
create policy "Employer teams manage milestones" on public.task_milestones
for all to authenticated using (
  exists (select 1 from public.freelance_contracts c where c.id = contract_id and (exists (select 1 from public.employers e where e.id = c.employer_id and e.owner_id = (select auth.uid())) or exists (select 1 from public.employer_members m where m.employer_id = c.employer_id and m.user_id = (select auth.uid()) and m.status='active')))
  or exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role='admin')
) with check (
  exists (select 1 from public.freelance_contracts c where c.id = contract_id and (exists (select 1 from public.employers e where e.id = c.employer_id and e.owner_id = (select auth.uid())) or exists (select 1 from public.employer_members m where m.employer_id = c.employer_id and m.user_id = (select auth.uid()) and m.status='active')))
  or exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role='admin')
);

create policy "Task messages readable by participants" on public.task_messages
for select to authenticated using (
  exists (select 1 from public.freelance_contracts c where c.id = contract_id and (c.freelancer_id = (select auth.uid()) or exists (select 1 from public.employers e where e.id = c.employer_id and e.owner_id = (select auth.uid())) or exists (select 1 from public.employer_members m where m.employer_id = c.employer_id and m.user_id = (select auth.uid()) and m.status='active')))
);
create policy "Task participants send messages" on public.task_messages
for insert to authenticated with check (
  sender_id = (select auth.uid()) and exists (select 1 from public.freelance_contracts c where c.id = contract_id and (c.freelancer_id = (select auth.uid()) or exists (select 1 from public.employers e where e.id = c.employer_id and e.owner_id = (select auth.uid())) or exists (select 1 from public.employer_members m where m.employer_id = c.employer_id and m.user_id = (select auth.uid()) and m.status='active')))
);

-- Mentorship catalog and workflow.
create policy "Active mentors public" on public.mentor_profiles
for select to anon using (active = true);
create policy "Mentors readable authenticated" on public.mentor_profiles
for select to authenticated using (active = true or user_id = (select auth.uid()) or exists (select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'));
create policy "Mentors create own profile" on public.mentor_profiles
for insert to authenticated with check (user_id = (select auth.uid()) and verified = false);
create policy "Mentors update own profile" on public.mentor_profiles
for update to authenticated using (user_id=(select auth.uid()) or exists (select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'))
with check (user_id=(select auth.uid()) or exists (select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'));
create policy "Mentors delete own profile" on public.mentor_profiles
for delete to authenticated using (user_id=(select auth.uid()) or exists (select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'));

create policy "Active mentor availability public" on public.mentor_availability
for select to anon, authenticated using (active = true);
create policy "Mentors manage availability" on public.mentor_availability
for all to authenticated using (mentor_id=(select auth.uid()) or exists (select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'))
with check (mentor_id=(select auth.uid()) or exists (select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'));

create policy "Mentorship requests readable by participants" on public.mentorship_requests
for select to authenticated using (mentor_id=(select auth.uid()) or mentee_id=(select auth.uid()) or exists (select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'));
create policy "Mentees create mentorship requests" on public.mentorship_requests
for insert to authenticated with check (mentee_id=(select auth.uid()) and status='pending');
create policy "Mentors respond to requests" on public.mentorship_requests
for update to authenticated using (mentor_id=(select auth.uid()) or exists (select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'))
with check (mentor_id=(select auth.uid()) or exists (select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'));
create policy "Mentees delete pending requests" on public.mentorship_requests
for delete to authenticated using (mentee_id=(select auth.uid()) and status='pending');

-- AI career coach: private to the owning user.
create policy "Coach sessions owner select" on public.career_coach_sessions
for select to authenticated using (user_id=(select auth.uid()));
create policy "Coach sessions owner insert" on public.career_coach_sessions
for insert to authenticated with check (user_id=(select auth.uid()));
create policy "Coach sessions owner update" on public.career_coach_sessions
for update to authenticated using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
create policy "Coach sessions owner delete" on public.career_coach_sessions
for delete to authenticated using (user_id=(select auth.uid()));

create policy "Coach messages owner select" on public.career_coach_messages
for select to authenticated using (exists (select 1 from public.career_coach_sessions s where s.id=session_id and s.user_id=(select auth.uid())));
create policy "Users add coach messages" on public.career_coach_messages
for insert to authenticated with check (role='user' and exists (select 1 from public.career_coach_sessions s where s.id=session_id and s.user_id=(select auth.uid())));

-- Notification preferences owner-only.
create policy "Notification preferences owner select" on public.notification_preferences
for select to authenticated using (user_id=(select auth.uid()));
create policy "Notification preferences owner insert" on public.notification_preferences
for insert to authenticated with check (user_id=(select auth.uid()));
create policy "Notification preferences owner update" on public.notification_preferences
for update to authenticated using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
create policy "Notification preferences owner delete" on public.notification_preferences
for delete to authenticated using (user_id=(select auth.uid()));

-- Reports/admin/analytics.
create policy "Users submit reports" on public.reports
for insert to authenticated with check (reporter_id=(select auth.uid()) and status='open' and assigned_to is null and resolved_at is null);
create policy "Reports readable by reporter or admin" on public.reports
for select to authenticated using (reporter_id=(select auth.uid()) or exists (select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'));
create policy "Admins update reports" on public.reports
for update to authenticated using (exists (select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'))
with check (exists (select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'));

create policy "Admins read audit logs" on public.admin_audit_logs
for select to authenticated using (exists (select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'));

create policy "Users create own analytics events" on public.platform_events
for insert to authenticated with check (user_id=(select auth.uid()));
create policy "Admins read analytics events" on public.platform_events
for select to authenticated using (exists (select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'));

;
