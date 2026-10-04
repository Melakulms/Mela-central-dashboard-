-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812202852
create index if not exists applications_reviewer_id_idx on public.applications(reviewer_id);
create index if not exists assessment_responses_question_idx on public.assessment_responses(question_id);
create index if not exists escrow_transactions_contract_idx on public.escrow_transactions(contract_id);
create index if not exists interviews_scheduled_by_idx on public.interviews(scheduled_by);
create index if not exists marketplace_tasks_employer_idx on public.marketplace_tasks(employer_id);
create index if not exists mentorship_sessions_request_idx on public.mentorship_sessions(request_id);
create index if not exists reports_assigned_to_idx on public.reports(assigned_to);
create index if not exists reports_reporter_idx on public.reports(reporter_id);
create index if not exists saved_candidates_candidate_idx on public.saved_candidates(candidate_id);
create index if not exists saved_candidates_saved_by_idx on public.saved_candidates(saved_by);
create index if not exists skill_assessments_created_by_idx on public.skill_assessments(created_by);
create index if not exists task_messages_sender_idx on public.task_messages(sender_id);

-- Avoid duplicate permissive SELECT policies on new tables.
drop policy if exists "Active mentor availability public" on public.mentor_availability;
create policy "Active mentor availability public anon" on public.mentor_availability
for select to anon using (active = true);
create policy "Mentor availability readable authenticated" on public.mentor_availability
for select to authenticated using (
  active = true or mentor_id = (select auth.uid()) or
  exists (select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin')
);
drop policy if exists "Mentors manage availability" on public.mentor_availability;
create policy "Mentors insert availability" on public.mentor_availability
for insert to authenticated with check (mentor_id=(select auth.uid()) or exists (select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'));
create policy "Mentors update availability" on public.mentor_availability
for update to authenticated using (mentor_id=(select auth.uid()) or exists (select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'))
with check (mentor_id=(select auth.uid()) or exists (select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'));
create policy "Mentors delete availability" on public.mentor_availability
for delete to authenticated using (mentor_id=(select auth.uid()) or exists (select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'));

drop policy if exists "Employer teams manage milestones" on public.task_milestones;
create policy "Employer teams insert milestones" on public.task_milestones
for insert to authenticated with check (
  exists (select 1 from public.freelance_contracts c where c.id = contract_id and (exists (select 1 from public.employers e where e.id = c.employer_id and e.owner_id = (select auth.uid())) or exists (select 1 from public.employer_members m where m.employer_id = c.employer_id and m.user_id = (select auth.uid()) and m.status='active')))
  or exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role='admin')
);
create policy "Employer teams update milestones" on public.task_milestones
for update to authenticated using (
  exists (select 1 from public.freelance_contracts c where c.id = contract_id and (exists (select 1 from public.employers e where e.id = c.employer_id and e.owner_id = (select auth.uid())) or exists (select 1 from public.employer_members m where m.employer_id = c.employer_id and m.user_id = (select auth.uid()) and m.status='active')))
  or exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role='admin')
) with check (
  exists (select 1 from public.freelance_contracts c where c.id = contract_id and (exists (select 1 from public.employers e where e.id = c.employer_id and e.owner_id = (select auth.uid())) or exists (select 1 from public.employer_members m where m.employer_id = c.employer_id and m.user_id = (select auth.uid()) and m.status='active')))
  or exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role='admin')
);
create policy "Employer teams delete milestones" on public.task_milestones
for delete to authenticated using (
  exists (select 1 from public.freelance_contracts c where c.id = contract_id and (exists (select 1 from public.employers e where e.id = c.employer_id and e.owner_id = (select auth.uid())) or exists (select 1 from public.employer_members m where m.employer_id = c.employer_id and m.user_id = (select auth.uid()) and m.status='active')))
  or exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role='admin')
);
;
