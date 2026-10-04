-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260822104915
revoke insert,update,delete on public.proctored_exams from authenticated; revoke insert,update,delete,select on public.study_materials from authenticated; revoke all on public.proctored_exams from anon; revoke all on public.study_materials from anon;
;
