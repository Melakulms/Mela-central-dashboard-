-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260809180909
create index if not exists ai_coach_sessions_course_idx on public.ai_coach_sessions(course_id, user_id, updated_at desc);
;
