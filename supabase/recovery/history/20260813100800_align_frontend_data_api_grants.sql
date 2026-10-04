-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260813100800
grant select, insert, update on table public.opportunities to authenticated;
grant select, insert, update on table public.applications to authenticated;
grant select, insert, update, delete on table public.saved_opportunities to authenticated;
grant select, insert, update on table public.interviews to authenticated;
grant select, insert, update, delete on table public.marketplace_tasks to authenticated;
grant select, insert, update on table public.marketplace_submissions to authenticated;
grant select, insert, update, delete on table public.mentor_profiles to authenticated;
grant select, insert, update on table public.mentorship_requests to authenticated;
grant select on table public.mentorship_sessions to authenticated;
grant select, insert, update on table public.student_lesson_progress to authenticated;
grant select, insert, update on table public.assessment_attempts to authenticated;
grant select, insert, update on table public.assessment_responses to authenticated;
grant select, update on table public.notifications to authenticated;
grant select, update on table public.profiles to authenticated;
grant select, insert, update on table public.employer_registration_requests to authenticated;
grant select, insert, update, delete on table public.payout_accounts to authenticated;
;
