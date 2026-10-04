-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260821235506
revoke select on public.arena_daily_metrics, public.course_enrollments, public.external_application_events, public.notifications, public.platform_events, public.user_badges, public.work_reputation from anon;
;
