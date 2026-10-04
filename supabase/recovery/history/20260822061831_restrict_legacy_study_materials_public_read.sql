-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260822061831
revoke select on table public.study_materials from public; revoke select on table public.study_materials from anon; revoke select on table public.study_materials from authenticated;
;
