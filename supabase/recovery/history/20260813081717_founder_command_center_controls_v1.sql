-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260813081717
create table if not exists public.platform_feature_flags (
  feature_key text primary key,
  label text not null,
  description text,
  enabled boolean not null default true,
  maintenance_message text,
  config jsonb not null default '{}'::jsonb,
  updated_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.platform_feature_flags enable row level security;
revoke all on public.platform_feature_flags from public, anon, authenticated;
grant select on public.platform_feature_flags to anon, authenticated;
grant all on public.platform_feature_flags to service_role;
drop policy if exists platform_feature_flags_read on public.platform_feature_flags;
create policy platform_feature_flags_read on public.platform_feature_flags for select to anon, authenticated using (true);

insert into public.platform_feature_flags(feature_key,label,description,enabled) values
 ('registrations','User registrations','Allow new Mela account registration',true),
 ('career_passport','Career Passport','Career Passport profiles and verification',true),
 ('academy','Skill Academy','Career paths, modules and lessons',true),
 ('practice','Practice Center','Practice sessions and AI practice coach',true),
 ('assessments','Assessments','Skill assessments and verification attempts',true),
 ('opportunities','Opportunity Hub','Jobs, internships and applications',true),
 ('scholarships','Scholarship Connect','Scholarship discovery and matching',true),
 ('arena','Arena','Competitive skills matches and tournaments',true),
 ('challenges','Company Challenges','Sponsored employer challenges',true),
 ('earn_work','Earn & Work','Freelance marketplace and contracts',true),
 ('payouts','Payouts','Real-money payout initiation and processing',false),
 ('mentorship','Mentorship','Mentor marketplace and sessions',true),
 ('video_calls','Video Calls','In-app video call rooms',true),
 ('ai_career_coach','AI Career Coach','Career coach sessions',true),
 ('ai_tutor','AI Tutor','Learning AI tutor sessions',true)
on conflict (feature_key) do nothing;

create table if not exists public.platform_announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  audience text not null default 'all' check (audience in ('all','student','employer','mentor','admin')),
  status text not null default 'draft' check (status in ('draft','published','archived')),
  starts_at timestamptz,
  ends_at timestamptz,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at is null or starts_at is null or ends_at > starts_at)
);
alter table public.platform_announcements enable row level security;
revoke all on public.platform_announcements from public, anon, authenticated;
grant select on public.platform_announcements to anon, authenticated;
grant all on public.platform_announcements to service_role;
drop policy if exists platform_announcements_read on public.platform_announcements;
create policy platform_announcements_read on public.platform_announcements for select to anon, authenticated
using (status='published' and (starts_at is null or starts_at<=now()) and (ends_at is null or ends_at>now()));
create index if not exists platform_announcements_status_time_idx on public.platform_announcements(status, starts_at, ends_at);

create or replace function public.admin_command_center_snapshot()
returns jsonb
language sql
set search_path='pg_catalog','public'
as $function$
select jsonb_build_object(
 'generated_at',now(),
 'data_quality',jsonb_build_object(
   'synthetic_test_profiles',(select count(*) from public.profiles where coalesce(email,'') ~* '@mela\\.invalid$'),
   'real_profiles',(select count(*) from public.profiles where coalesce(email,'') !~* '@mela\\.invalid$')
 ),
 'users',jsonb_build_object(
   'total',(select count(*) from public.profiles where coalesce(email,'') !~* '@mela\\.invalid$'),
   'new_today',(select count(*) from public.profiles where coalesce(email,'') !~* '@mela\\.invalid$' and created_at>=date_trunc('day',now())),
   'new_7d',(select count(*) from public.profiles where coalesce(email,'') !~* '@mela\\.invalid$' and created_at>=now()-interval '7 days'),
   'active_24h',(select count(distinct e.user_id) from public.platform_events e join public.profiles p on p.id=e.user_id where coalesce(p.email,'') !~* '@mela\\.invalid$' and e.created_at>=now()-interval '24 hours'),
   'students',(select count(*) from public.profiles where role='student'::public.user_role and coalesce(email,'') !~* '@mela\\.invalid$'),
   'employers',(select count(*) from public.profiles where role='employer'::public.user_role and coalesce(email,'') !~* '@mela\\.invalid$'),
   'mentors',(select count(*) from public.profiles where role='mentor'::public.user_role and coalesce(email,'') !~* '@mela\\.invalid$'),
   'admins',(select count(*) from public.profiles where role='admin'::public.user_role and coalesce(email,'') !~* '@mela\\.invalid$'),
   'contact_verified',(select count(*) from public.profiles where coalesce(email,'') !~* '@mela\\.invalid$' and (coalesce(email_verified,false) or coalesce(phone_verified,false)))
 ),
 'employers',jsonb_build_object(
   'companies',(select count(*) from public.employers e join public.profiles p on p.id=e.owner_id where coalesce(p.email,'') !~* '@mela\\.invalid$'),
   'verified',(select count(*) from public.employers e join public.profiles p on p.id=e.owner_id where coalesce(p.email,'') !~* '@mela\\.invalid$' and e.verified=true),
   'pending_registrations',(select count(*) from public.employer_registration_requests r join public.profiles p on p.id=r.applicant_user_id where coalesce(p.email,'') !~* '@mela\\.invalid$' and r.status in ('pending','under_review')),
   'suspended',(select count(*) from public.employers e join public.profiles p on p.id=e.owner_id where coalesce(p.email,'') !~* '@mela\\.invalid$' and e.verification_status='suspended')
 ),
 'opportunities',jsonb_build_object(
   'total',(select count(*) from public.opportunities),
   'open',(select count(*) from public.opportunities where status='open' and verified_active=true and (deadline is null or deadline>=current_date)),
   'closing_7d',(select count(*) from public.opportunities where status='open' and verified_active=true and deadline between current_date and current_date+7),
   'applications',(select count(*) from public.applications a join public.profiles p on p.id=coalesce(a.applicant_id,a.user_id) where coalesce(p.email,'') !~* '@mela\\.invalid$'),
   'applications_7d',(select count(*) from public.applications a join public.profiles p on p.id=coalesce(a.applicant_id,a.user_id) where coalesce(p.email,'') !~* '@mela\\.invalid$' and a.applied_at>=now()-interval '7 days'),
   'hired',(select count(*) from public.applications a join public.profiles p on p.id=coalesce(a.applicant_id,a.user_id) where coalesce(p.email,'') !~* '@mela\\.invalid$' and a.status='hired'),
   'scholarships',(select count(*) from public.scholarship_details)
 ),
 'learning',jsonb_build_object(
   'career_paths',(select count(*) from public.career_paths),
   'active_enrollments',(select count(*) from public.career_path_enrollments e join public.profiles p on p.id=e.user_id where coalesce(p.email,'') !~* '@mela\\.invalid$' and e.status in ('enrolled','in_progress')),
   'completed_enrollments',(select count(*) from public.career_path_enrollments e join public.profiles p on p.id=e.user_id where coalesce(p.email,'') !~* '@mela\\.invalid$' and e.status='completed'),
   'practice_sessions_7d',(select count(*) from public.practice_sessions s join public.profiles p on p.id=s.user_id where coalesce(p.email,'') !~* '@mela\\.invalid$' and s.created_at>=now()-interval '7 days'),
   'published_assessments',(select count(*) from public.skill_assessments where status='published'),
   'assessment_attempts',(select count(*) from public.assessment_attempts a join public.profiles p on p.id=a.user_id where coalesce(p.email,'') !~* '@mela\\.invalid$'),
   'assessment_review_required',(select count(*) from public.assessment_attempts a join public.profiles p on p.id=a.user_id where coalesce(p.email,'') !~* '@mela\\.invalid$' and a.status='review_required'),
   'verified_skills',(select count(*) from public.verified_skills v join public.profiles p on p.id=v.user_id where coalesce(p.email,'') !~* '@mela\\.invalid$' and v.verified=true)
 ),
 'arena',jsonb_build_object(
   'matches_7d',(select count(*) from public.arena_matches where created_at>=now()-interval '7 days'),
   'live_matches',(select count(*) from public.arena_matches where status='live'),
   'completed_30d',(select count(*) from public.arena_matches where status='completed' and ended_at>=now()-interval '30 days'),
   'active_tournaments',(select count(*) from public.arena_tournaments where status in ('registration','in_progress')),
   'integrity_attention',(select count(*) from public.arena_integrity_summaries s join public.profiles p on p.id=s.user_id where coalesce(p.email,'') !~* '@mela\\.invalid$' and s.status in ('review','flagged','disqualified')),
   'pending_cash_rewards',(select count(*) from public.arena_rewards r join public.profiles p on p.id=r.beneficiary_user_id where coalesce(p.email,'') !~* '@mela\\.invalid$' and r.reward_type='cash' and r.status in ('pending','available'))
 ),
 'work',jsonb_build_object(
   'open_tasks',(select count(*) from public.marketplace_tasks where status='open'),
   'contracts',(select count(*) from public.freelance_contracts c join public.profiles p on p.id=c.freelancer_id where coalesce(p.email,'') !~* '@mela\\.invalid$'),
   'active_contracts',(select count(*) from public.freelance_contracts c join public.profiles p on p.id=c.freelancer_id where coalesce(p.email,'') !~* '@mela\\.invalid$' and c.status='active'),
   'completed_contracts',(select count(*) from public.freelance_contracts c join public.profiles p on p.id=c.freelancer_id where coalesce(p.email,'') !~* '@mela\\.invalid$' and c.status='completed'),
   'pending_payouts',(select count(*) from public.payout_requests r join public.profiles p on p.id=r.freelancer_id where coalesce(p.email,'') !~* '@mela\\.invalid$' and r.status in ('pending','queued')),
   'failed_payouts',(select count(*) from public.payout_requests r join public.profiles p on p.id=r.freelancer_id where coalesce(p.email,'') !~* '@mela\\.invalid$' and r.status='failed')
 ),
 'finance',jsonb_build_object(
   'escrow_held_count',(select count(*) from public.escrow_transactions e join public.freelance_contracts c on c.id=e.contract_id join public.profiles p on p.id=c.freelancer_id where coalesce(p.email,'') !~* '@mela\\.invalid$' and e.status='held'),
   'escrow_held_etb',(select coalesce(sum(e.amount_minor),0)::numeric/100 from public.escrow_transactions e join public.freelance_contracts c on c.id=e.contract_id join public.profiles p on p.id=c.freelancer_id where coalesce(p.email,'') !~* '@mela\\.invalid$' and e.status='held' and upper(coalesce(e.currency,'ETB'))='ETB'),
   'pending_payout_etb',(select coalesce(sum(r.amount_minor),0)::numeric/100 from public.payout_requests r join public.profiles p on p.id=r.freelancer_id where coalesce(p.email,'') !~* '@mela\\.invalid$' and r.status in ('pending','queued') and upper(coalesce(r.currency,'ETB'))='ETB'),
   'user_net_earned_30d_etb',(select coalesce(sum(l.net_amount),0) from public.earnings_ledger l join public.profiles p on p.id=l.user_id where coalesce(p.email,'') !~* '@mela\\.invalid$' and l.occurred_at>=now()-interval '30 days' and upper(coalesce(l.currency,'ETB'))='ETB'),
   'platform_fees_30d_etb',(select coalesce(sum(l.platform_fee),0) from public.earnings_ledger l join public.profiles p on p.id=l.user_id where coalesce(p.email,'') !~* '@mela\\.invalid$' and l.occurred_at>=now()-interval '30 days' and upper(coalesce(l.currency,'ETB'))='ETB')
 ),
 'scholarships',jsonb_build_object(
   'records',(select count(*) from public.scholarship_details),
   'closing_30d',(select count(*) from public.scholarship_details s join public.opportunities o on o.id=s.opportunity_id where o.status='open' and o.deadline between current_date and current_date+30),
   'source_verified_30d',(select count(*) from public.scholarship_details where source_verified_at>=now()-interval '30 days')
 ),
 'ai',jsonb_build_object(
   'career_coach_calls_24h',(select count(*) from public.career_coach_usage u join public.profiles p on p.id=u.user_id where coalesce(p.email,'') !~* '@mela\\.invalid$' and u.created_at>=now()-interval '24 hours'),
   'career_coach_calls_30d',(select count(*) from public.career_coach_usage u join public.profiles p on p.id=u.user_id where coalesce(p.email,'') !~* '@mela\\.invalid$' and u.created_at>=now()-interval '30 days'),
   'ai_tutor_calls_30d',(select count(*) from public.ai_tutor_usage u join public.profiles p on p.id=u.user_id where coalesce(p.email,'') !~* '@mela\\.invalid$' and u.created_at>=now()-interval '30 days')
 ),
 'video',jsonb_build_object(
   'rooms_total',(select count(*) from public.video_call_rooms v join public.profiles p on p.id=v.created_by where coalesce(p.email,'') !~* '@mela\\.invalid$'),
   'rooms_active',(select count(*) from public.video_call_rooms v join public.profiles p on p.id=v.created_by where coalesce(p.email,'') !~* '@mela\\.invalid$' and v.status in ('open','live')),
   'rooms_30d',(select count(*) from public.video_call_rooms v join public.profiles p on p.id=v.created_by where coalesce(p.email,'') !~* '@mela\\.invalid$' and v.created_at>=now()-interval '30 days'),
   'recordings_ready',(select count(*) from public.video_call_rooms v join public.profiles p on p.id=v.created_by where coalesce(p.email,'') !~* '@mela\\.invalid$' and v.recording_status='completed' and v.recording_path is not null)
 ),
 'moderation',jsonb_build_object(
   'open_reports',(select count(*) from public.reports r join public.profiles p on p.id=r.reporter_id where coalesce(p.email,'') !~* '@mela\\.invalid$' and r.status='open'),
   'reviewing_reports',(select count(*) from public.reports r join public.profiles p on p.id=r.reporter_id where coalesce(p.email,'') !~* '@mela\\.invalid$' and r.status='reviewing'),
   'pending_employers',(select count(*) from public.employer_registration_requests r join public.profiles p on p.id=r.applicant_user_id where coalesce(p.email,'') !~* '@mela\\.invalid$' and r.status in ('pending','under_review')),
   'pending_mentors',(select count(*) from public.mentor_profiles m join public.profiles p on p.id=m.user_id where coalesce(p.email,'') !~* '@mela\\.invalid$' and m.verified=false and m.active=true),
   'proctor_review_required',(select count(*) from public.assessment_attempts a join public.profiles p on p.id=a.user_id where coalesce(p.email,'') !~* '@mela\\.invalid$' and a.status='review_required'),
   'pending_payouts',(select count(*) from public.payout_requests r join public.profiles p on p.id=r.freelancer_id where coalesce(p.email,'') !~* '@mela\\.invalid$' and r.status in ('pending','queued'))
 )
);
$function$;
revoke all on function public.admin_command_center_snapshot() from public, anon, authenticated;
grant execute on function public.admin_command_center_snapshot() to service_role;

;
