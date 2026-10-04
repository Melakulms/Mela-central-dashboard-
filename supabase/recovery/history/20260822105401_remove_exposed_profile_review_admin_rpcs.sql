-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260822105401
revoke execute on function public.review_employer_document(uuid,text,text) from authenticated; revoke execute on function public.review_profile_document(uuid,boolean,text,text) from authenticated; revoke execute on function public.review_profile_education(uuid,boolean,text,text) from authenticated; revoke execute on function public.review_profile_experience(uuid,boolean,text,text) from authenticated; revoke execute on function public.review_profile_language(uuid,boolean,text,text) from authenticated;
;
