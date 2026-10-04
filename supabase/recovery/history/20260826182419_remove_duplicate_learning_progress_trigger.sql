-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260826182419
DROP TRIGGER IF EXISTS trg_guard_student_learning_progress_mutation ON public.student_lesson_progress;
;
