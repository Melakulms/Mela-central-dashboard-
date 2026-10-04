-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812214629
-- Service-role-only aggregate metrics for the admin Edge Function.
create or replace function public.admin_dashboard_metrics()
returns jsonb
language sql
security definer
set search_path='pg_catalog','public'
as $$
select jsonb_build_object(
  'users', jsonb_build_object(
    'total',(select count(*) from public.profiles),
    'students',(select count(*) from public.profiles where role='student'::public.user_role),
    'employers',(select count(*) from public.profiles where role='employer'::public.user_role),
    'mentors',(select count(*) from public.profiles where role='mentor'::public.user_role),
    'admins',(select count(*) from public.profiles where role='admin'::public.user_role)
  ),
  'employers',jsonb_build_object(
    'companies',(select count(*) from public.employers),
    'verified',(select count(*) from public.employers where verified=true),
    'pending_registrations',(select count(*) from public.employer_registration_requests where status in ('pending','under_review'))
  ),
  'talent',jsonb_build_object(
    'verified_skills',(select count(*) from public.verified_skills where verified=true),
    'badges_earned',(select count(*) from public.user_badges),
    'career_paths',(select count(*) from public.career_paths),
    'lessons',(select count(*) from public.path_lessons where is_published=true)
  ),
  'assessments',jsonb_build_object(
    'published',(select count(*) from public.skill_assessments where status='published'),
    'attempts',(select count(*) from public.assessment_attempts),
    'review_required',(select count(*) from public.assessment_attempts where status='review_required')
  ),
  'opportunities',jsonb_build_object(
    'total',(select count(*) from public.opportunities),
    'open',(select count(*) from public.opportunities where status='open' and verified_active=true and deadline>=current_date),
    'applications',(select count(*) from public.applications),
    'hired',(select count(*) from public.applications where status='hired')
  ),
  'mentorship',jsonb_build_object(
    'verified_mentors',(select count(*) from public.mentor_profiles where verified=true and active=true),
    'pending_requests',(select count(*) from public.mentorship_requests where status='pending'),
    'sessions',(select count(*) from public.mentorship_sessions),
    'completed_sessions',(select count(*) from public.mentorship_sessions where status='completed')
  ),
  'freelance',jsonb_build_object(
    'open_tasks',(select count(*) from public.marketplace_tasks where status='open'),
    'contracts',(select count(*) from public.freelance_contracts),
    'active_contracts',(select count(*) from public.freelance_contracts where status='active'),
    'escrow_held',(select count(*) from public.escrow_transactions where status='held'),
    'pending_payouts',(select count(*) from public.payout_requests where status in ('pending','queued'))
  ),
  'moderation',jsonb_build_object(
    'open_reports',(select count(*) from public.reports where status='open'),
    'reviewing_reports',(select count(*) from public.reports where status='reviewing')
  ),
  'ai',jsonb_build_object(
    'career_coach_messages_30d',(select count(*) from public.career_coach_usage where created_at>=now()-interval '30 days'),
    'tutor_messages_30d',(select count(*) from public.ai_tutor_usage where created_at>=now()-interval '30 days')
  ),
  'generated_at',now()
);$$;
revoke all on function public.admin_dashboard_metrics() from public,anon,authenticated;
grant execute on function public.admin_dashboard_metrics() to service_role;

-- New tables explicitly grant service_role full access (important for Data API changes).
grant all on public.escrow_payment_attempts,public.payout_accounts,public.payout_requests,public.proctor_reviews,public.career_coach_usage to service_role;
revoke all on public.escrow_payment_attempts,public.payout_accounts,public.payout_requests,public.proctor_reviews,public.career_coach_usage from anon;

-- Admin audit is immutable through the browser.
revoke insert,update,delete on public.admin_audit_logs from authenticated,anon;
grant all on public.admin_audit_logs to service_role;

-- Explicit service grants for operational tables used by Edge Functions.
grant all on public.notifications,public.platform_events,public.reports,public.employer_registration_requests,public.employers,public.mentor_profiles,public.proctor_audit_logs,public.assessment_attempts,public.marketplace_tasks,public.marketplace_submissions,public.freelance_contracts,public.task_milestones,public.escrow_transactions,public.career_coach_sessions,public.career_coach_messages,public.ai_coach_sessions,public.ai_tutor_usage to service_role;

;
