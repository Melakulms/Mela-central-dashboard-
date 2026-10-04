-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260822104959
revoke select on public.proctored_exams from authenticated;
;
