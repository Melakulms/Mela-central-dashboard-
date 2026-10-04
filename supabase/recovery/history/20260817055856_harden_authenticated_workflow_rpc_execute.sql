-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260817055856
revoke execute on function public.request_my_guardian_consent(text,text,text) from public, anon;
revoke execute on function public.review_guardian_consent(uuid,text,text) from public, anon;
revoke execute on function public.refresh_my_school_safety_status() from public, anon;
revoke execute on function public.set_my_education_context(text,smallint,text) from public, anon;
revoke execute on function public.get_my_assessment_language_review_assignments() from public, anon;
revoke execute on function public.get_my_partner_dashboard() from public, anon;
revoke execute on function public.review_sector_partner_registration(uuid,text,text) from public, anon;
revoke execute on function public.submit_task_milestone(uuid,text,text) from public, anon;
grant execute on function public.request_my_guardian_consent(text,text,text) to authenticated, service_role;
grant execute on function public.review_guardian_consent(uuid,text,text) to authenticated, service_role;
grant execute on function public.refresh_my_school_safety_status() to authenticated, service_role;
grant execute on function public.set_my_education_context(text,smallint,text) to authenticated, service_role;
grant execute on function public.get_my_assessment_language_review_assignments() to authenticated, service_role;
grant execute on function public.get_my_partner_dashboard() to authenticated, service_role;
grant execute on function public.review_sector_partner_registration(uuid,text,text) to authenticated, service_role;
grant execute on function public.submit_task_milestone(uuid,text,text) to authenticated, service_role;
;
