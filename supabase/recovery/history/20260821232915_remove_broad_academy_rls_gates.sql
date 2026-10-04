-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260821232915
drop policy if exists mela_gate_academy on public.lesson_progress;
drop policy if exists mela_gate_academy on public.student_lesson_progress;
drop policy if exists mela_gate_academy on public.student_module_progress;
;
