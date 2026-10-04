-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260822090343
drop policy if exists "Students create own lesson progress" on public.student_lesson_progress; drop policy if exists "Students update own lesson progress" on public.student_lesson_progress; drop policy if exists "Students create own module progress" on public.student_module_progress; drop policy if exists "Students update own module progress" on public.student_module_progress; revoke insert, update, delete on public.student_lesson_progress from authenticated; revoke insert, update, delete on public.student_module_progress from authenticated;
;
