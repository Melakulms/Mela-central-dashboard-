-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260822105042
create policy "Backend controlled proctored exams" on public.proctored_exams as restrictive for all to authenticated using (false) with check (false); create policy "Backend controlled study materials" on public.study_materials as restrictive for all to authenticated using (false) with check (false);
;
