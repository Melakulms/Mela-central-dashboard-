-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260822105311
revoke execute on function public.admin_assign_assessment_language_reviewer(uuid,text,uuid) from authenticated; revoke execute on function public.admin_certify_assessment_language(uuid,text,text) from authenticated; revoke execute on function public.admin_qualify_assessment_language_reviewer(uuid,text,boolean,text) from authenticated; revoke execute on function public.admin_get_assessment_language_review_status() from authenticated;
;
