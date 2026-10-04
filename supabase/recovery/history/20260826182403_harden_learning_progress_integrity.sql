-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260826182403
CREATE OR REPLACE FUNCTION public.guard_learning_progress_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP='UPDATE' AND NOT public.is_admin_user(auth.uid()) THEN
    IF NEW.user_id IS DISTINCT FROM OLD.user_id
       OR NEW.lesson_id IS DISTINCT FROM OLD.lesson_id
       OR NEW.completed_at IS DISTINCT FROM OLD.completed_at THEN
      RAISE EXCEPTION 'Learning progress identity/completion fields are protected';
    END IF;
    IF TG_TABLE_NAME='student_lesson_progress' AND NEW.progress_percent < OLD.progress_percent THEN
      RAISE EXCEPTION 'Learning progress cannot decrease';
    END IF;
    IF TG_TABLE_NAME='student_lesson_progress' AND NEW.time_spent_seconds < OLD.time_spent_seconds THEN
      RAISE EXCEPTION 'Learning time cannot decrease';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_guard_learning_progress_mutation ON public.lesson_progress;
CREATE TRIGGER trg_guard_learning_progress_mutation BEFORE UPDATE ON public.lesson_progress FOR EACH ROW EXECUTE FUNCTION public.guard_learning_progress_mutation();
DROP TRIGGER IF EXISTS trg_guard_student_learning_progress_mutation ON public.student_lesson_progress;
CREATE TRIGGER trg_guard_student_learning_progress_mutation BEFORE UPDATE ON public.student_lesson_progress FOR EACH ROW EXECUTE FUNCTION public.guard_learning_progress_mutation();

ALTER TABLE public.course_enrollments DROP CONSTRAINT IF EXISTS course_enrollments_progress_valid;
ALTER TABLE public.course_enrollments ADD CONSTRAINT course_enrollments_progress_valid CHECK (progress_pct BETWEEN 0 AND 100);
ALTER TABLE public.student_lesson_progress DROP CONSTRAINT IF EXISTS student_lesson_progress_progress_valid;
ALTER TABLE public.student_lesson_progress ADD CONSTRAINT student_lesson_progress_progress_valid CHECK (progress_percent BETWEEN 0 AND 100 AND time_spent_seconds >= 0);
;
