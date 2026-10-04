-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812221421
-- Cover all newly introduced foreign keys reported by the Performance Advisor.
create index if not exists arena_invites_invited_by_idx on public.arena_invites(invited_by);
create index if not exists arena_matches_assessment_idx on public.arena_matches(assessment_id);
create index if not exists arena_matches_sponsored_challenge_idx on public.arena_matches(sponsored_challenge_id);
create index if not exists arena_participants_team_idx on public.arena_participants(team_id);
create index if not exists arena_round_submissions_match_idx on public.arena_round_submissions(match_id);
create index if not exists arena_round_submissions_reviewed_by_idx on public.arena_round_submissions(reviewed_by);
create index if not exists arena_rounds_assessment_question_idx on public.arena_rounds(assessment_question_id);
create index if not exists arena_team_members_user_idx on public.arena_team_members(user_id);
create index if not exists arena_teams_captain_idx on public.arena_teams(captain_id);
create index if not exists coach_action_plans_session_idx on public.career_coach_action_plans(session_id);
create index if not exists challenge_judges_assigned_by_idx on public.challenge_judges(assigned_by);
create index if not exists challenge_participants_team_idx on public.challenge_participants(team_id);
create index if not exists challenge_reviews_judge_idx on public.challenge_reviews(judge_id);
create index if not exists challenge_rewards_team_idx on public.challenge_rewards(beneficiary_team_id);
create index if not exists challenge_rewards_submission_idx on public.challenge_rewards(submission_id);
create index if not exists challenge_submissions_team_idx on public.challenge_submissions(team_id);
create index if not exists challenge_teams_captain_idx on public.challenge_teams(captain_id);
create index if not exists opportunity_reminders_opportunity_idx on public.opportunity_reminders(opportunity_id);
create index if not exists academy_certificates_path_idx on public.skill_academy_certificates(career_path_id);
create index if not exists sponsored_challenges_created_by_idx on public.sponsored_challenges(created_by);
create index if not exists sponsored_challenges_winner_submission_idx on public.sponsored_challenges(winner_submission_id);
create index if not exists video_call_events_actor_idx on public.video_call_events(actor_id);
create index if not exists video_call_participants_invited_by_idx on public.video_call_participants(invited_by);
create index if not exists video_call_signals_recipient_idx on public.video_call_signals(recipient_id);
create index if not exists video_call_signals_sender_idx on public.video_call_signals(sender_id);
create index if not exists work_reviews_reviewer_idx on public.work_reviews(reviewer_user_id);

-- Arena: split ALL into write-only policies so SELECT has only one permissive policy.
drop policy if exists "Arena creator manages rounds" on public.arena_rounds;
drop policy if exists "Arena creator inserts rounds" on public.arena_rounds;
create policy "Arena creator inserts rounds" on public.arena_rounds for insert to authenticated
with check (exists(select 1 from public.arena_matches m where m.id=match_id and (m.creator_id=(select auth.uid()) or private.is_admin_user()) and m.status in ('draft','open')));
drop policy if exists "Arena creator updates rounds" on public.arena_rounds;
create policy "Arena creator updates rounds" on public.arena_rounds for update to authenticated
using (exists(select 1 from public.arena_matches m where m.id=match_id and (m.creator_id=(select auth.uid()) or private.is_admin_user()) and m.status in ('draft','open')))
with check (exists(select 1 from public.arena_matches m where m.id=match_id and (m.creator_id=(select auth.uid()) or private.is_admin_user()) and m.status in ('draft','open')));
drop policy if exists "Arena creator deletes rounds" on public.arena_rounds;
create policy "Arena creator deletes rounds" on public.arena_rounds for delete to authenticated
using (exists(select 1 from public.arena_matches m where m.id=match_id and (m.creator_id=(select auth.uid()) or private.is_admin_user()) and m.status in ('draft','open')));

-- Escrow: retain the broader participant policy only.
drop policy if exists "Escrow readable by contract participants" on public.escrow_transactions;

-- Marketplace proposal updates: preserve the union of admin, student, and employer permissions in one policy.
drop policy if exists "Admins update proposals" on public.marketplace_submissions;
drop policy if exists "Employer teams review proposals" on public.marketplace_submissions;
drop policy if exists "Students edit or withdraw pending proposals" on public.marketplace_submissions;
drop policy if exists "Marketplace proposal updates" on public.marketplace_submissions;
create policy "Marketplace proposal updates" on public.marketplace_submissions for update to authenticated
using (
  private.is_admin_user()
  or (user_id=(select auth.uid()) and status='pending')
  or (status='pending' and exists(select 1 from public.marketplace_tasks t where t.id=task_id and private.has_employer_access(t.employer_id,true)))
)
with check (
  private.is_admin_user()
  or (user_id=(select auth.uid()) and status in ('pending','withdrawn'))
  or (exists(select 1 from public.marketplace_tasks t where t.id=task_id and private.has_employer_access(t.employer_id,true)) and status in ('shortlisted','accepted','rejected'))
);

-- Marketplace task public read: keep the stricter open/unassigned policy.
drop policy if exists "Marketplace tasks public read" on public.marketplace_tasks;

-- Marketplace task delete: merge draft/unassigned delete rules.
drop policy if exists "Employer teams delete draft marketplace tasks" on public.marketplace_tasks;
drop policy if exists "Employer teams delete unassigned tasks" on public.marketplace_tasks;
drop policy if exists "Employer teams delete marketplace tasks" on public.marketplace_tasks;
create policy "Employer teams delete marketplace tasks" on public.marketplace_tasks for delete to authenticated
using (
  (private.has_employer_access(employer_id,true) or private.is_admin_user())
  and status in ('draft','open','cancelled','expired')
  and not exists(select 1 from public.freelance_contracts c where c.task_id=id)
);

-- Mentorship request state transitions: merge admin, mentee cancel, and mentor response policies.
drop policy if exists "Admins update mentorship requests" on public.mentorship_requests;
drop policy if exists "Mentees cancel pending requests" on public.mentorship_requests;
drop policy if exists "Mentors respond to requests" on public.mentorship_requests;
drop policy if exists "Mentorship request state updates" on public.mentorship_requests;
create policy "Mentorship request state updates" on public.mentorship_requests for update to authenticated
using (
  private.is_admin_user()
  or (mentee_id=(select auth.uid()) and status='pending')
  or (mentor_id=(select auth.uid()) and status='pending')
)
with check (
  private.is_admin_user()
  or (mentee_id=(select auth.uid()) and status='cancelled')
  or (mentor_id=(select auth.uid()) and status in ('accepted','declined'))
);

;
