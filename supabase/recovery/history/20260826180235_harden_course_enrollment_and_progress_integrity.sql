-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260826180235
CREATE OR REPLACE FUNCTION public.guard_course_enrollment_integrity()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF TG_OP='UPDATE' THEN
    IF NEW.user_id IS DISTINCT FROM OLD.user_id OR NEW.course_id IS DISTINCT FROM OLD.course_id OR NEW.enrolled_at IS DISTINCT FROM OLD.enrolled_at THEN
      IF NOT public.is_admin_user(auth.uid()) THEN RAISE EXCEPTION 'Enrollment identity fields are immutable'; END IF;
    END IF;
    IF NEW.progress_pct < OLD.progress_pct AND NOT public.is_admin_user(auth.uid()) THEN RAISE EXCEPTION 'Course progress cannot decrease'; END IF;
    IF OLD.completed_at IS NOT NULL AND NEW.completed_at IS DISTINCT FROM OLD.completed_at AND NOT public.is_admin_user(auth.uid()) THEN RAISE EXCEPTION 'Completed enrollment is immutable'; END IF;
    IF NEW.progress_pct=100 AND NEW.completed_at IS NULL THEN NEW.completed_at=now(); END IF;
  END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_guard_course_enrollment_integrity ON public.course_enrollments;
CREATE TRIGGER trg_guard_course_enrollment_integrity BEFORE UPDATE ON public.course_enrollments FOR EACH ROW EXECUTE FUNCTION public.guard_course_enrollment_integrity();

ALTER TABLE public.course_enrollments DROP CONSTRAINT IF EXISTS course_enrollments_progress_valid;
ALTER TABLE public.course_enrollments ADD CONSTRAINT course_enrollments_progress_valid CHECK (progress_pct BETWEEN 0 AND 100);

CREATE OR REPLACE FUNCTION public.guard_lesson_progress_integrity()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF TG_OP='UPDATE' THEN
    IF NEW.user_id IS DISTINCT FROM OLD.user_id OR NEW.lesson_id IS DISTINCT FROM OLD.lesson_id OR NEW.completed_at IS DISTINCT FROM OLD.completed_at THEN
      IF NOT public.is_admin_user(auth.uid()) THEN RAISE EXCEPTION 'Lesson progress identity/completion fields are immutable'; END IF;
    END IF;
  END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_guard_lesson_progress_integrity ON public.lesson_progress;
CREATE TRIGGER trg_guard_lesson_progress_integrity BEFORE UPDATE ON public.lesson_progress FOR EACH ROW EXECUTE FUNCTION public.guard_lesson_progress_integrity();

CREATE UNIQUE INDEX IF NOT EXISTS ux_lesson_progress_user_lesson ON public.lesson_progress(user_id,lesson_id);
CREATE UNIQUE INDEX IF NOT EXISTS ux_course_enrollment_user_course ON public.course_enrollments(user_id,course_id);
;
