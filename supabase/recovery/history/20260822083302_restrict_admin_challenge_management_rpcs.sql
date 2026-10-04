-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260822083302
revoke execute on function public.assign_challenge_judge(uuid,uuid) from anon, authenticated; revoke execute on function public.remove_challenge_judge(uuid,uuid) from anon, authenticated; revoke execute on function public.review_mentor_profile(uuid,boolean,text) from anon, authenticated; revoke execute on function public.review_arena_submission(uuid,numeric,text) from anon, authenticated;
;
