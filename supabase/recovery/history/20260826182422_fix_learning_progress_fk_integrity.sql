-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260826182422
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.student_lesson_progress'::regclass AND conname='student_lesson_progress_lesson_id_fkey') THEN
    ALTER TABLE public.student_lesson_progress DROP CONSTRAINT student_lesson_progress_lesson_id_fkey;
  END IF;
END $$;

UPDATE public.student_lesson_progress s
SET lesson_id = NULL
WHERE NOT EXISTS (SELECT 1 FROM public.path_lessons l WHERE l.id=s.lesson_id);

ALTER TABLE public.student_lesson_progress
  ALTER COLUMN lesson_id DROP NOT NULL;

ALTER TABLE public.student_lesson_progress
  ADD CONSTRAINT student_lesson_progress_lesson_id_fkey
  FOREIGN KEY (lesson_id) REFERENCES public.path_lessons(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_student_lesson_progress_user_lesson
  ON public.student_lesson_progress(user_id, lesson_id);
;
