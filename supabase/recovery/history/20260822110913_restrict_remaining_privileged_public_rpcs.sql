-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260822110913
revoke execute on function public.admin_update_platform_launch_requirement(text,text,text,text) from authenticated; revoke execute on function public.admin_upsert_external_opportunity(uuid,text,text,text,text,date,launch_category,opportunity_type,text,text,text,text,text,text[],text[],text,text) from authenticated; revoke execute on function public.finalize_sponsored_challenge(uuid) from authenticated;
;
