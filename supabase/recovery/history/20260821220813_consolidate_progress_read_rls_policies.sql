-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260821220813
DROP POLICY IF EXISTS lesson_progress_self_select ON public.lesson_progress;
DROP POLICY IF EXISTS parent_read_lesson_progress_v35 ON public.lesson_progress;
CREATE POLICY lesson_progress_read_self_or_verified_parent
ON public.lesson_progress
FOR SELECT TO authenticated
USING (
  (user_id = (SELECT auth.uid()))
  OR private.has_verified_guardian_link((SELECT auth.uid()), user_id)
);

DROP POLICY IF EXISTS "Students view own lesson progress" ON public.student_lesson_progress;
DROP POLICY IF EXISTS parent_read_student_lesson_progress_v35 ON public.student_lesson_progress;
CREATE POLICY student_lesson_progress_read_self_or_verified_parent
ON public.student_lesson_progress
FOR SELECT TO authenticated
USING (
  (user_id = (SELECT auth.uid()))
  OR private.has_verified_guardian_link((SELECT auth.uid()), user_id)
);

DROP POLICY IF EXISTS "Students view own module progress" ON public.student_module_progress;
DROP POLICY IF EXISTS parent_read_student_module_progress_v35 ON public.student_module_progress;
CREATE POLICY student_module_progress_read_self_or_verified_parent
ON public.student_module_progress
FOR SELECT TO authenticated
USING (
  (user_id = (SELECT auth.uid()))
  OR private.has_verified_guardian_link((SELECT auth.uid()), user_id)
);
;
