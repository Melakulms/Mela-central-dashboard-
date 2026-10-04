-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20261002192608
revoke execute on function public.get_my_guardian_learner_progress(uuid) from anon;
grant execute on function public.get_my_guardian_learner_progress(uuid) to authenticated;
;
