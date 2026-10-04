-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260813082403
create or replace function public.admin_command_center_snapshot_v2()
returns jsonb
language sql
set search_path='pg_catalog','public'
as $function$
with real_profiles as materialized (
  select * from public.profiles where lower(coalesce(email,'')) not like '%@mela.invalid'
), test_profiles as materialized (
  select * from public.profiles where lower(coalesce(email,'')) like '%@mela.invalid'
)
select jsonb_build_object(
 'generated_at',now(),
 'data_quality',jsonb_build_object(
   'synthetic_test_profiles',(select count(*) from test_profiles),
   'real_profiles',(select count(*) from real_profiles)
 ),
 'users',jsonb_build_object(
   'total',(select count(*) from real_profiles),
   'new_today',(select count(*) from real_profiles where created_at>=date_trunc('day',now())),
   'new_7d',(select count(*) from real_profiles where created_at>=now()-interval '7 days'),
   'active_24h',(select count(distinct e.user_id) from public.platform_events e join real_profiles p on p.id=e.user_id where e.created_at>=now()-interval '24 hours'),
   'students',(select count(*) from real_profiles where role='student'::public.user_role),
   'employers',(select count(*) from real_profiles where role='employer'::public.user_role),
   'mentors',(select count(*) from real_profiles where role='mentor'::public.user_role),
   'admins',(select count(*) from real_profiles where role='admin'::public.user_role),
   'contact_verified',(select count(*) from real_profiles where coalesce(email_verified,false) or coalesce(phone_verified,false))
 ),
 'employers',jsonb_build_object(
   'companies',(select count(*) from public.employers e join real_profiles p on p.id=e.owner_id),
   'verified',(select count(*) from public.employers e join real_profiles p on p.id=e.owner_id where e.verified=true),
   'pending_registrations',(select count(*) from public.employer_registration_requests r join real_profiles p on p.id=r.applicant_user_id where r.status in ('pending','under_review')),
   'suspended',(select count(*) from public.employers e join real_profiles p on p.id=e.owner_id where e.verification_status='suspended')
 ),
 'opportunities',jsonb_build_object(
   'total',(select count(*) from public.opportunities),
   'open',(select count(*) from public.opportunities where status='open' and verified_active=true and (deadline is null or deadline>=current_date)),
   'closing_7d',(select count(*) from public.opportunities where status='open' and verified_active=true and deadline between current_date and current_date+7),
   'applications',(select count(*) from public.applications a join real_profiles p on p.id=coalesce(a.applicant_id,a.user_id)),
   'applications_7d',(select count(*) from public.applications a join real_profiles p on p.id=coalesce(a.applicant_id,a.user_id) where a.applied_at>=now()-interval '7 days'),
   'hired',(select count(*) from public.applications a join real_profiles p on p.id=coalesce(a.applicant_id,a.user_id) where a.status='hired'),
   'scholarships',(select count(*) from public.scholarship_details)
 ),
 'learning',jsonb_build_object(
   'career_paths',(select count(*) from public.career_paths),
   'active_enrollments',(select count(*) from public.career_path_enrollments e join real_profiles p on p.id=e.user_id where e.status in ('enrolled','in_progress')),
   'completed_enrollments',(select count(*) from public.career_path_enrollments e join real_profiles p on p.id=e.user_id where e.status='completed'),
   'practice_sessions_7d',(select count(*) from public.practice_sessions s join real_profiles p on p.id=s.user_id where s.created_at>=now()-interval '7 days'),
   'published_assessments',(select count(*) from public.skill_assessments where status='published'),
   'assessment_attempts',(select count(*) from public.assessment_attempts a join real_profiles p on p.id=a.user_id),
   'assessment_review_required',(select count(*) from public.assessment_attempts a join real_profiles p on p.id=a.user_id where a.status='review_required'),
   'verified_skills',(select count(*) from public.verified_skills v join real_profiles p on p.id=v.user_id where v.verified=true)
 ),
 'arena',jsonb_build_object(
   'matches_7d',(select count(*) from public.arena_matches where created_at>=now()-interval '7 days'),
   'live_matches',(select count(*) from public.arena_matches where status='live'),
   'completed_30d',(select count(*) from public.arena_matches where status='completed' and ended_at>=now()-interval '30 days'),
   'active_tournaments',(select count(*) from public.arena_tournaments where status in ('registration','in_progress')),
   'integrity_attention',(select count(*) from public.arena_integrity_summaries s join real_profiles p on p.id=s.user_id where s.status in ('review','flagged','disqualified')),
   'pending_cash_rewards',(select count(*) from public.arena_rewards r join real_profiles p on p.id=r.beneficiary_user_id where r.reward_type='cash' and r.status in ('pending','available'))
 ),
 'work',jsonb_build_object(
   'open_tasks',(select count(*) from public.marketplace_tasks t left join public.employers e on e.id=t.employer_id left join real_profiles p on p.id=e.owner_id where t.status='open' and (t.employer_id is null or p.id is not null)),
   'contracts',(select count(*) from public.freelance_contracts c join real_profiles p on p.id=c.freelancer_id),
   'active_contracts',(select count(*) from public.freelance_contracts c join real_profiles p on p.id=c.freelancer_id where c.status='active'),
   'completed_contracts',(select count(*) from public.freelance_contracts c join real_profiles p on p.id=c.freelancer_id where c.status='completed'),
   'pending_payouts',(select count(*) from public.payout_requests r join real_profiles p on p.id=r.freelancer_id where r.status in ('pending','queued')),
   'failed_payouts',(select count(*) from public.payout_requests r join real_profiles p on p.id=r.freelancer_id where r.status='failed')
 ),
 'finance',jsonb_build_object(
   'escrow_held_count',(select count(*) from public.escrow_transactions e join public.freelance_contracts c on c.id=e.contract_id join real_profiles p on p.id=c.freelancer_id where e.status='held'),
   'escrow_held_etb',(select coalesce(sum(e.amount_minor),0)::numeric/100 from public.escrow_transactions e join public.freelance_contracts c on c.id=e.contract_id join real_profiles p on p.id=c.freelancer_id where e.status='held' and upper(coalesce(e.currency,'ETB'))='ETB'),
   'pending_payout_etb',(select coalesce(sum(r.amount_minor),0)::numeric/100 from public.payout_requests r join real_profiles p on p.id=r.freelancer_id where r.status in ('pending','queued') and upper(coalesce(r.currency,'ETB'))='ETB'),
   'user_net_earned_30d_etb',(select coalesce(sum(l.net_amount),0) from public.earnings_ledger l join real_profiles p on p.id=l.user_id where l.occurred_at>=now()-interval '30 days' and upper(coalesce(l.currency,'ETB'))='ETB'),
   'platform_fees_30d_etb',(select coalesce(sum(l.platform_fee),0) from public.earnings_ledger l join real_profiles p on p.id=l.user_id where l.occurred_at>=now()-interval '30 days' and upper(coalesce(l.currency,'ETB'))='ETB')
 ),
 'scholarships',jsonb_build_object(
   'records',(select count(*) from public.scholarship_details),
   'closing_30d',(select count(*) from public.scholarship_details s join public.opportunities o on o.id=s.opportunity_id where o.status='open' and o.deadline between current_date and current_date+30),
   'source_verified_30d',(select count(*) from public.scholarship_details where source_verified_at>=now()-interval '30 days')
 ),
 'ai',jsonb_build_object(
   'career_coach_calls_24h',(select count(*) from public.career_coach_usage u join real_profiles p on p.id=u.user_id where u.created_at>=now()-interval '24 hours'),
   'career_coach_calls_30d',(select count(*) from public.career_coach_usage u join real_profiles p on p.id=u.user_id where u.created_at>=now()-interval '30 days'),
   'ai_tutor_calls_30d',(select count(*) from public.ai_tutor_usage u join real_profiles p on p.id=u.user_id where u.created_at>=now()-interval '30 days')
 ),
 'video',jsonb_build_object(
   'rooms_total',(select count(*) from public.video_call_rooms v join real_profiles p on p.id=v.created_by),
   'rooms_active',(select count(*) from public.video_call_rooms v join real_profiles p on p.id=v.created_by where v.status in ('open','live')),
   'rooms_30d',(select count(*) from public.video_call_rooms v join real_profiles p on p.id=v.created_by where v.created_at>=now()-interval '30 days'),
   'recordings_ready',(select count(*) from public.video_call_rooms v join real_profiles p on p.id=v.created_by where v.recording_status='completed' and v.recording_path is not null)
 ),
 'moderation',jsonb_build_object(
   'open_reports',(select count(*) from public.reports r join real_profiles p on p.id=r.reporter_id where r.status='open'),
   'reviewing_reports',(select count(*) from public.reports r join real_profiles p on p.id=r.reporter_id where r.status='reviewing'),
   'pending_employers',(select count(*) from public.employer_registration_requests r join real_profiles p on p.id=r.applicant_user_id where r.status in ('pending','under_review')),
   'pending_mentors',(select count(*) from public.mentor_profiles m join real_profiles p on p.id=m.user_id where m.verified=false and m.active=true),
   'proctor_review_required',(select count(*) from public.assessment_attempts a join real_profiles p on p.id=a.user_id where a.status='review_required'),
   'pending_payouts',(select count(*) from public.payout_requests r join real_profiles p on p.id=r.freelancer_id where r.status in ('pending','queued'))
 )
);
$function$;
revoke all on function public.admin_command_center_snapshot_v2() from public, anon, authenticated;
grant execute on function public.admin_command_center_snapshot_v2() to service_role;
;
