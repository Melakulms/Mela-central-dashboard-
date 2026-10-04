-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260813072456
create or replace function public.admin_command_center_snapshot()
returns jsonb
language sql
security invoker
set search_path to 'pg_catalog','public'
as $$
select jsonb_build_object(
  'generated_at', now(),
  'users', jsonb_build_object(
    'total',(select count(*) from public.profiles),
    'new_today',(select count(*) from public.profiles where created_at>=date_trunc('day',now())),
    'new_7d',(select count(*) from public.profiles where created_at>=now()-interval '7 days'),
    'active_24h',(select count(distinct user_id) from public.platform_events where user_id is not null and created_at>=now()-interval '24 hours'),
    'students',(select count(*) from public.profiles where role='student'::public.user_role),
    'employers',(select count(*) from public.profiles where role='employer'::public.user_role),
    'mentors',(select count(*) from public.profiles where role='mentor'::public.user_role),
    'admins',(select count(*) from public.profiles where role='admin'::public.user_role),
    'contact_verified',(select count(*) from public.profiles where coalesce(email_verified,false)=true or coalesce(phone_verified,false)=true)
  ),
  'employers', jsonb_build_object(
    'companies',(select count(*) from public.employers),
    'verified',(select count(*) from public.employers where verified=true),
    'pending_registrations',(select count(*) from public.employer_registration_requests where status in ('pending','under_review')),
    'suspended',(select count(*) from public.employers where verification_status='suspended')
  ),
  'opportunities', jsonb_build_object(
    'total',(select count(*) from public.opportunities),
    'open',(select count(*) from public.opportunities where status='open' and verified_active=true and (deadline is null or deadline>=current_date)),
    'closing_7d',(select count(*) from public.opportunities where status='open' and verified_active=true and deadline between current_date and current_date+7),
    'applications',(select count(*) from public.applications),
    'applications_7d',(select count(*) from public.applications where applied_at>=now()-interval '7 days'),
    'hired',(select count(*) from public.applications where status='hired'),
    'scholarships',(select count(*) from public.scholarship_details)
  ),
  'learning', jsonb_build_object(
    'career_paths',(select count(*) from public.career_paths),
    'active_enrollments',(select count(*) from public.career_path_enrollments where status in ('enrolled','in_progress')),
    'completed_enrollments',(select count(*) from public.career_path_enrollments where status='completed'),
    'practice_sessions_7d',(select count(*) from public.practice_sessions where created_at>=now()-interval '7 days'),
    'published_assessments',(select count(*) from public.skill_assessments where status='published'),
    'assessment_attempts',(select count(*) from public.assessment_attempts),
    'assessment_review_required',(select count(*) from public.assessment_attempts where status='review_required'),
    'verified_skills',(select count(*) from public.verified_skills where verified=true)
  ),
  'arena', jsonb_build_object(
    'matches_7d',(select count(*) from public.arena_matches where created_at>=now()-interval '7 days'),
    'live_matches',(select count(*) from public.arena_matches where status='live'),
    'completed_30d',(select count(*) from public.arena_matches where status='completed' and ended_at>=now()-interval '30 days'),
    'active_tournaments',(select count(*) from public.arena_tournaments where status in ('registration','in_progress')),
    'integrity_attention',(select count(*) from public.arena_integrity_summaries where status in ('review','flagged','disqualified')),
    'pending_cash_rewards',(select count(*) from public.arena_rewards where reward_type='cash' and status in ('pending','available'))
  ),
  'work', jsonb_build_object(
    'open_tasks',(select count(*) from public.marketplace_tasks where status='open'),
    'contracts',(select count(*) from public.freelance_contracts),
    'active_contracts',(select count(*) from public.freelance_contracts where status='active'),
    'completed_contracts',(select count(*) from public.freelance_contracts where status='completed'),
    'pending_payouts',(select count(*) from public.payout_requests where status in ('pending','queued')),
    'failed_payouts',(select count(*) from public.payout_requests where status='failed')
  ),
  'finance', jsonb_build_object(
    'escrow_held_count',(select count(*) from public.escrow_transactions where status='held'),
    'escrow_held_etb',(select coalesce(sum(amount_minor),0)::numeric/100 from public.escrow_transactions where status='held' and upper(coalesce(currency,'ETB'))='ETB'),
    'pending_payout_etb',(select coalesce(sum(amount_minor),0)::numeric/100 from public.payout_requests where status in ('pending','queued') and upper(coalesce(currency,'ETB'))='ETB'),
    'user_net_earned_30d_etb',(select coalesce(sum(net_amount),0) from public.earnings_ledger where occurred_at>=now()-interval '30 days' and upper(coalesce(currency,'ETB'))='ETB'),
    'platform_fees_30d_etb',(select coalesce(sum(platform_fee),0) from public.earnings_ledger where occurred_at>=now()-interval '30 days' and upper(coalesce(currency,'ETB'))='ETB')
  ),
  'scholarships', jsonb_build_object(
    'records',(select count(*) from public.scholarship_details),
    'closing_30d',(select count(*) from public.scholarship_details s join public.opportunities o on o.id=s.opportunity_id where o.status='open' and o.deadline between current_date and current_date+30),
    'source_verified_30d',(select count(*) from public.scholarship_details where source_verified_at>=now()-interval '30 days')
  ),
  'ai', jsonb_build_object(
    'career_coach_calls_24h',(select count(*) from public.career_coach_usage where created_at>=now()-interval '24 hours'),
    'career_coach_calls_30d',(select count(*) from public.career_coach_usage where created_at>=now()-interval '30 days'),
    'ai_tutor_calls_30d',(select count(*) from public.ai_tutor_usage where created_at>=now()-interval '30 days')
  ),
  'video', jsonb_build_object(
    'rooms_total',(select count(*) from public.video_call_rooms),
    'rooms_active',(select count(*) from public.video_call_rooms where status='active'),
    'rooms_30d',(select count(*) from public.video_call_rooms where created_at>=now()-interval '30 days'),
    'recordings_ready',(select count(*) from public.video_call_rooms where recording_status='completed' and recording_path is not null)
  ),
  'moderation', jsonb_build_object(
    'open_reports',(select count(*) from public.reports where status='open'),
    'reviewing_reports',(select count(*) from public.reports where status='reviewing'),
    'pending_employers',(select count(*) from public.employer_registration_requests where status in ('pending','under_review')),
    'pending_mentors',(select count(*) from public.mentor_profiles where verified=false and active=true),
    'proctor_review_required',(select count(*) from public.assessment_attempts where status='review_required'),
    'pending_payouts',(select count(*) from public.payout_requests where status in ('pending','queued'))
  )
);
$$;

revoke all on function public.admin_command_center_snapshot() from public, anon, authenticated;
grant execute on function public.admin_command_center_snapshot() to service_role;

;
