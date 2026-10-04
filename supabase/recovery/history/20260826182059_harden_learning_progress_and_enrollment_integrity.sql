-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260826182059
ALTER TABLE public.course_enrollments DROP CONSTRAINT IF EXISTS course_enrollments_progress_valid;
ALTER TABLE public.course_enrollments ADD CONSTRAINT course_enrollments_progress_valid CHECK (progress_pct BETWEEN 0 AND 100);

ALTER TABLE public.student_lesson_progress DROP CONSTRAINT IF EXISTS student_lesson_progress_values_valid;
ALTER TABLE public.student_lesson_progress ADD CONSTRAINT student_lesson_progress_values_valid CHECK (progress_percent BETWEEN 0 AND 100 AND time_spent_seconds >= 0);

ALTER TABLE public.student_module_progress DROP CONSTRAINT IF EXISTS student_module_progress_values_valid;
ALTER TABLE public.student_module_progress ADD CONSTRAINT student_module_progress_values_valid CHECK (quiz_score IS NULL OR quiz_score BETWEEN 0 AND 100);

ALTER TABLE public.course_enrollments DROP CONSTRAINT IF EXISTS uq_course_enrollment_user_course;
ALTER TABLE public.course_enrollments ADD CONSTRAINT uq_course_enrollment_user_course UNIQUE (user_id, course_id);

CREATE OR REPLACE FUNCTION public.guard_learning_progress_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  IF TG_OP='UPDATE' AND NOT private.is_admin_user() THEN
    IF NEW.user_id IS DISTINCT FROM OLD.user_id OR NEW.lesson_id IS DISTINCT FROM OLD.lesson_id THEN
      RAISE EXCEPTION 'Learning progress identity is immutable';
    END IF;
    IF NEW.progress_percent < OLD.progress_percent THEN
      RAISE EXCEPTION 'Learning progress cannot decrease';
    END IF;
    IF NEW.completed_at IS NOT NULL AND OLD.completed_at IS NOT NULL AND NEW.completed_at IS DISTINCT FROM OLD.completed_at THEN
      RAISE EXCEPTION 'Completion timestamp is immutable';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_guard_learning_progress_mutation ON public.student_lesson_progress;
CREATE TRIGGER trg_guard_learning_progress_mutation BEFORE UPDATE ON public.student_lesson_progress FOR EACH ROW EXECUTE FUNCTION public.guard_learning_progress_mutation();

CREATE OR REPLACE FUNCTION public.guard_module_progress_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  IF TG_OP='UPDATE' AND NOT private.is_admin_user() THEN
    IF NEW.user_id IS DISTINCT FROM OLD.user_id OR NEW.module_id IS DISTINCT FROM OLD.module_id THEN
      RAISE EXCEPTION 'Module progress identity is immutable';
    END IF;
    IF OLD.completed IS TRUE AND NEW.completed IS FALSE THEN
      RAISE EXCEPTION 'Completed modules cannot be uncompleted';
    END IF;
    IF OLD.proctored_passed IS TRUE AND NEW.proctored_passed IS FALSE THEN
      RAISE EXCEPTION 'Proctored pass cannot be revoked by a normal user';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_guard_module_progress_mutation ON public.student_module_progress;
CREATE TRIGGER trg_guard_module_progress_mutation BEFORE UPDATE ON public.student_module_progress FOR EACH ROW EXECUTE FUNCTION public.guard_module_progress_mutation();
;
