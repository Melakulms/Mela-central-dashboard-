-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260826182007
ALTER TABLE public.courses DROP CONSTRAINT IF EXISTS courses_price_duration_valid;
ALTER TABLE public.courses ADD CONSTRAINT courses_price_duration_valid CHECK (price_cents >= 0 AND duration_minutes > 0 AND (featured_rank IS NULL OR featured_rank > 0));
ALTER TABLE public.course_lessons DROP CONSTRAINT IF EXISTS course_lessons_positions_duration_valid;
ALTER TABLE public.course_lessons ADD CONSTRAINT course_lessons_positions_duration_valid CHECK (module_position > 0 AND lesson_position > 0 AND duration_minutes > 0);
CREATE UNIQUE INDEX IF NOT EXISTS course_lessons_unique_position ON public.course_lessons(course_id,module_position,lesson_position);
ALTER TABLE public.course_enrollments DROP CONSTRAINT IF EXISTS course_enrollments_progress_valid;
ALTER TABLE public.course_enrollments ADD CONSTRAINT course_enrollments_progress_valid CHECK (progress_pct BETWEEN 0 AND 100 AND ((progress_pct = 100 AND completed_at IS NOT NULL) OR (progress_pct < 100 AND completed_at IS NULL)));
CREATE UNIQUE INDEX IF NOT EXISTS course_enrollments_unique_user_course ON public.course_enrollments(user_id,course_id);

CREATE OR REPLACE FUNCTION public.guard_course_enrollment_identity()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF TG_OP='UPDATE' AND (NEW.user_id IS DISTINCT FROM OLD.user_id OR NEW.course_id IS DISTINCT FROM OLD.course_id OR NEW.enrolled_at IS DISTINCT FROM OLD.enrolled_at) THEN
    IF NOT public.is_admin_user(auth.uid()) THEN RAISE EXCEPTION 'Course enrollment identity is immutable'; END IF;
  END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_guard_course_enrollment_identity ON public.course_enrollments;
CREATE TRIGGER trg_guard_course_enrollment_identity BEFORE UPDATE ON public.course_enrollments FOR EACH ROW EXECUTE FUNCTION public.guard_course_enrollment_identity();
;
