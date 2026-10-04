-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260822104620
revoke execute on function public.promote_generated_question_candidate_v18(uuid) from authenticated; revoke execute on function public.review_generated_question_candidate_v18(uuid,text,text) from authenticated;
;
