-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260826182038
ALTER TABLE public.course_enrollments DROP CONSTRAINT IF EXISTS course_enrollments_progress_valid;
ALTER TABLE public.course_enrollments ADD CONSTRAINT course_enrollments_progress_valid CHECK (progress_pct BETWEEN 0 AND 100 AND (completed_at IS NULL OR progress_pct = 100) AND (completed_at IS NULL OR completed_at >= enrolled_at));

ALTER TABLE public.course_lessons DROP CONSTRAINT IF EXISTS course_lessons_positions_valid;
ALTER TABLE public.course_lessons ADD CONSTRAINT course_lessons_positions_valid CHECK (module_position > 0 AND lesson_position > 0 AND duration_minutes > 0);

ALTER TABLE public.student_lesson_progress DROP CONSTRAINT IF EXISTS student_lesson_progress_values_valid;
ALTER TABLE public.student_lesson_progress ADD CONSTRAINT student_lesson_progress_values_valid CHECK (progress_percent BETWEEN 0 AND 100 AND time_spent_seconds >= 0 AND (completed_at IS NULL OR (progress_percent = 100 AND status = 'completed')) AND (completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at));

ALTER TABLE public.lesson_progress DROP CONSTRAINT IF EXISTS lesson_progress_completed_valid;
ALTER TABLE public.lesson_progress ADD CONSTRAINT lesson_progress_completed_valid CHECK (completed_at <= now());

CREATE UNIQUE INDEX IF NOT EXISTS ux_course_enrollments_user_course ON public.course_enrollments(user_id,course_id);
CREATE UNIQUE INDEX IF NOT EXISTS ux_student_lesson_progress_user_lesson ON public.student_lesson_progress(user_id,lesson_id);
CREATE UNIQUE INDEX IF NOT EXISTS ux_lesson_progress_user_lesson ON public.lesson_progress(user_id,lesson_id);

CREATE OR REPLACE FUNCTION public.guard_course_enrollment_identity()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF TG_OP='UPDATE' AND (NEW.user_id IS DISTINCT FROM OLD.user_id OR NEW.course_id IS DISTINCT FROM OLD.course_id) AND NOT public.is_admin_user(auth.uid()) THEN
    RAISE EXCEPTION 'Course enrollment identity is immutable for non-admin users';
  END IF;
  IF TG_OP='UPDATE' AND NEW.enrolled_at IS DISTINCT FROM OLD.enrolled_at AND NOT public.is_admin_user(auth.uid()) THEN
    RAISE EXCEPTION 'Enrollment timestamp is immutable for non-admin users';
  END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_guard_course_enrollment_identity ON public.course_enrollments;
CREATE TRIGGER trg_guard_course_enrollment_identity BEFORE UPDATE ON public.course_enrollments FOR EACH ROW EXECUTE FUNCTION public.guard_course_enrollment_identity();

CREATE OR REPLACE FUNCTION public.guard_student_lesson_progress_identity()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF TG_OP='UPDATE' AND (NEW.user_id IS DISTINCT FROM OLD.user_id OR NEW.lesson_id IS DISTINCT FROM OLD.lesson_id OR NEW.created_at IS DISTINCT FROM OLD.created_at) AND NOT public.is_admin_user(auth.uid()) THEN
    RAISE EXCEPTION 'Lesson progress identity is immutable for non-admin users';
  END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_guard_student_lesson_progress_identity ON public.student_lesson_progress;
CREATE TRIGGER trg_guard_student_lesson_progress_identity BEFORE UPDATE ON public.student_lesson_progress FOR EACH ROW EXECUTE FUNCTION public.guard_student_lesson_progress_identity();
;
