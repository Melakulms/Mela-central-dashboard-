-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260822063604
drop policy if exists "study_materials: public read" on public.study_materials; drop policy if exists "exams: public read" on public.proctored_exams;
;
