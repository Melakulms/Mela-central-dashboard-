-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260826180050
ALTER TABLE public.courses DROP CONSTRAINT IF EXISTS courses_learning_terms_valid;
ALTER TABLE public.courses ADD CONSTRAINT courses_learning_terms_valid CHECK (price_cents >= 0 AND duration_minutes > 0 AND btrim(title) <> '');

ALTER TABLE public.course_lessons DROP CONSTRAINT IF EXISTS course_lessons_learning_terms_valid;
ALTER TABLE public.course_lessons ADD CONSTRAINT course_lessons_learning_terms_valid CHECK (module_position >= 1 AND lesson_position >= 1 AND duration_minutes > 0 AND btrim(title) <> '' AND btrim(content_text) <> '');

ALTER TABLE public.course_enrollments DROP CONSTRAINT IF EXISTS course_enrollments_progress_valid;
ALTER TABLE public.course_enrollments ADD CONSTRAINT course_enrollments_progress_valid CHECK (progress_pct BETWEEN 0 AND 100);

ALTER TABLE public.student_lesson_progress DROP CONSTRAINT IF EXISTS student_lesson_progress_values_valid;
ALTER TABLE public.student_lesson_progress ADD CONSTRAINT student_lesson_progress_values_valid CHECK (progress_percent BETWEEN 0 AND 100 AND time_spent_seconds >= 0);

ALTER TABLE public.student_module_progress DROP CONSTRAINT IF EXISTS student_module_progress_quiz_valid;
ALTER TABLE public.student_module_progress ADD CONSTRAINT student_module_progress_quiz_valid CHECK (quiz_score IS NULL OR quiz_score BETWEEN 0 AND 100);

CREATE UNIQUE INDEX IF NOT EXISTS course_enrollments_user_course_unique ON public.course_enrollments(user_id,course_id);
CREATE UNIQUE INDEX IF NOT EXISTS lesson_progress_user_lesson_unique ON public.lesson_progress(user_id,lesson_id);
CREATE UNIQUE INDEX IF NOT EXISTS student_lesson_progress_user_lesson_unique ON public.student_lesson_progress(user_id,lesson_id);
CREATE UNIQUE INDEX IF NOT EXISTS student_module_progress_user_module_unique ON public.student_module_progress(user_id,module_id);

CREATE OR REPLACE FUNCTION public.guard_course_enrollment_identity()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
 IF TG_OP='UPDATE' AND (NEW.user_id IS DISTINCT FROM OLD.user_id OR NEW.course_id IS DISTINCT FROM OLD.course_id) AND NOT public.is_admin_user(auth.uid()) THEN
  RAISE EXCEPTION 'Course enrollment identity is immutable';
 END IF;
 RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_guard_course_enrollment_identity ON public.course_enrollments;
CREATE TRIGGER trg_guard_course_enrollment_identity BEFORE UPDATE ON public.course_enrollments FOR EACH ROW EXECUTE FUNCTION public.guard_course_enrollment_identity();

CREATE OR REPLACE FUNCTION public.guard_course_progress_identity()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
 IF TG_OP='UPDATE' AND (NEW.user_id IS DISTINCT FROM OLD.user_id OR NEW.lesson_id IS DISTINCT FROM OLD.lesson_id) AND NOT public.is_admin_user(auth.uid()) THEN
  RAISE EXCEPTION 'Learning progress identity is immutable';
 END IF;
 RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_guard_lesson_progress_identity ON public.lesson_progress;
CREATE TRIGGER trg_guard_lesson_progress_identity BEFORE UPDATE ON public.lesson_progress FOR EACH ROW EXECUTE FUNCTION public.guard_course_progress_identity();
DROP TRIGGER IF EXISTS trg_guard_student_lesson_progress_identity ON public.student_lesson_progress;
CREATE TRIGGER trg_guard_student_lesson_progress_identity BEFORE UPDATE ON public.student_lesson_progress FOR EACH ROW EXECUTE FUNCTION public.guard_course_progress_identity();
;
