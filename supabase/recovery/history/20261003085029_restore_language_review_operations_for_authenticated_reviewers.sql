-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20261003085029
-- Reviewer-facing workflow: expose only SECURITY INVOKER wrappers while the
-- private implementations enforce assignment + qualification ownership.
create or replace function public.get_my_assessment_language_review(p_assessment_id uuid,p_language_code text)
returns jsonb
language sql
security invoker
set search_path to ''
as $function$
  select private.get_my_assessment_language_review(p_assessment_id,p_language_code);
$function$;

revoke all on function private.get_my_assessment_language_review(uuid,text) from public,anon;
grant execute on function private.get_my_assessment_language_review(uuid,text) to authenticated,service_role;
revoke all on function public.get_my_assessment_language_review(uuid,text) from public,anon;
grant execute on function public.get_my_assessment_language_review(uuid,text) to authenticated,service_role;

revoke all on function private.submit_assessment_language_review(uuid,text,text,text) from public,anon;
grant execute on function private.submit_assessment_language_review(uuid,text,text,text) to authenticated,service_role;
revoke all on function public.submit_assessment_language_review(uuid,text,text,text) from public,anon;
grant execute on function public.submit_assessment_language_review(uuid,text,text,text) to authenticated,service_role;

-- MFA-admin operations. Public wrappers stay SECURITY INVOKER; private
-- implementations verify private.is_admin_user(), which requires AAL2 for admins.
revoke all on function private.admin_get_assessment_language_review_status() from public,anon;
grant execute on function private.admin_get_assessment_language_review_status() to authenticated,service_role;
revoke all on function public.admin_get_assessment_language_review_status() from public,anon;
grant execute on function public.admin_get_assessment_language_review_status() to authenticated,service_role;

revoke all on function private.admin_qualify_assessment_language_reviewer(uuid,text,boolean,text) from public,anon;
grant execute on function private.admin_qualify_assessment_language_reviewer(uuid,text,boolean,text) to authenticated,service_role;
revoke all on function public.admin_qualify_assessment_language_reviewer(uuid,text,boolean,text) from public,anon;
grant execute on function public.admin_qualify_assessment_language_reviewer(uuid,text,boolean,text) to authenticated,service_role;

revoke all on function private.admin_assign_assessment_language_reviewer(uuid,text,uuid) from public,anon;
grant execute on function private.admin_assign_assessment_language_reviewer(uuid,text,uuid) to authenticated,service_role;
revoke all on function public.admin_assign_assessment_language_reviewer(uuid,text,uuid) from public,anon;
grant execute on function public.admin_assign_assessment_language_reviewer(uuid,text,uuid) to authenticated,service_role;

revoke all on function private.admin_certify_assessment_language(uuid,text,text) from public,anon;
grant execute on function private.admin_certify_assessment_language(uuid,text,text) to authenticated,service_role;
revoke all on function public.admin_certify_assessment_language(uuid,text,text) from public,anon;
grant execute on function public.admin_certify_assessment_language(uuid,text,text) to authenticated,service_role;

;
