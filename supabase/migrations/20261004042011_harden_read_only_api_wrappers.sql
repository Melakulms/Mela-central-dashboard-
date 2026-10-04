create or replace function public.get_data_protection_compliance_pack()
returns jsonb
language sql
security invoker
set search_path to ''
as $function$ select private.get_data_protection_compliance_pack(); $function$;

create or replace function public.get_my_question_bank_overview()
returns jsonb
language sql
stable
security invoker
set search_path to ''
as $function$ select private.get_my_question_bank_overview(); $function$;

create or replace function public.get_question_catalog_v18(p_grade_level smallint default null)
returns jsonb
language sql
stable
security invoker
set search_path to ''
as $function$ select private.get_question_catalog_v18(p_grade_level); $function$;

create or replace function public.get_question_quality_progress_v21()
returns jsonb
language sql
stable
security invoker
set search_path to ''
as $function$ select private.get_question_quality_progress_v21(); $function$;

create or replace function public.get_question_subject_detail_v18(p_program_key text)
returns jsonb
language sql
stable
security invoker
set search_path to ''
as $function$ select private.get_question_subject_detail_v18(p_program_key); $function$;

revoke all on function private.get_data_protection_compliance_pack() from public, anon;
revoke all on function private.get_my_question_bank_overview() from public, anon;
revoke all on function private.get_question_catalog_v18(smallint) from public, anon;
revoke all on function private.get_question_quality_progress_v21() from public, anon;
revoke all on function private.get_question_subject_detail_v18(text) from public, anon;
grant execute on function private.get_data_protection_compliance_pack() to authenticated, service_role;
grant execute on function private.get_my_question_bank_overview() to authenticated, service_role;
grant execute on function private.get_question_catalog_v18(smallint) to authenticated, service_role;
grant execute on function private.get_question_quality_progress_v21() to authenticated, service_role;
grant execute on function private.get_question_subject_detail_v18(text) to authenticated, service_role;

revoke all on function public.get_data_protection_compliance_pack() from public, anon;
revoke all on function public.get_my_question_bank_overview() from public, anon;
revoke all on function public.get_question_catalog_v18(smallint) from public, anon;
revoke all on function public.get_question_quality_progress_v21() from public, anon;
revoke all on function public.get_question_subject_detail_v18(text) from public, anon;
grant execute on function public.get_data_protection_compliance_pack() to authenticated, service_role;
grant execute on function public.get_my_question_bank_overview() to authenticated, service_role;
grant execute on function public.get_question_catalog_v18(smallint) to authenticated, service_role;
grant execute on function public.get_question_quality_progress_v21() to authenticated, service_role;
grant execute on function public.get_question_subject_detail_v18(text) to authenticated, service_role;
