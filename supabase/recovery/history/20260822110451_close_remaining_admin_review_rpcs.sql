-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260822110451
revoke execute on function public.review_opportunity_v35(uuid,text,text) from authenticated; revoke execute on function public.review_proctored_attempt(uuid,text,text) from authenticated; revoke execute on function public.review_report(uuid,text,text,uuid) from authenticated; revoke execute on function public.review_sector_partner_registration(uuid,text,text) from authenticated;
;
