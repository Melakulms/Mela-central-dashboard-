-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260826182105
ALTER TABLE public.courses DROP CONSTRAINT IF EXISTS courses_level_valid;
ALTER TABLE public.courses ADD CONSTRAINT courses_level_valid CHECK (lower(btrim(level)) IN ('beginner','intermediate','advanced','expert'));
ALTER TABLE public.courses DROP CONSTRAINT IF EXISTS courses_price_duration_valid;
ALTER TABLE public.courses ADD CONSTRAINT courses_price_duration_valid CHECK (price_cents >= 0 AND duration_minutes >= 0);
ALTER TABLE public.course_lessons DROP CONSTRAINT IF EXISTS course_lessons_positions_valid;
ALTER TABLE public.course_lessons ADD CONSTRAINT course_lessons_positions_valid CHECK (module_position >= 1 AND lesson_position >= 1 AND duration_minutes >= 0 AND btrim(title) <> '');
ALTER TABLE public.course_enrollments DROP CONSTRAINT IF EXISTS course_enrollments_progress_valid;
ALTER TABLE public.course_enrollments ADD CONSTRAINT course_enrollments_progress_valid CHECK (progress_pct BETWEEN 0 AND 100 AND (progress_pct < 100 OR completed_at IS NOT NULL));
ALTER TABLE public.student_lesson_progress DROP CONSTRAINT IF EXISTS student_lesson_progress_valid;
ALTER TABLE public.student_lesson_progress ADD CONSTRAINT student_lesson_progress_valid CHECK (progress_percent BETWEEN 0 AND 100 AND time_spent_seconds >= 0 AND ((status='completed' AND progress_percent=100 AND completed_at IS NOT NULL) OR (status<>'completed' AND completed_at IS NULL)));
CREATE UNIQUE INDEX IF NOT EXISTS course_enrollments_user_course_uidx ON public.course_enrollments(user_id,course_id);
CREATE UNIQUE INDEX IF NOT EXISTS student_lesson_progress_user_lesson_uidx ON public.student_lesson_progress(user_id,lesson_id);
;
