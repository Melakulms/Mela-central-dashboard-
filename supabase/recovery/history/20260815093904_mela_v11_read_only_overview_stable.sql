-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815093904
create or replace function public.get_my_question_bank_overview()
returns jsonb
language sql
stable
security invoker
set search_path to ''
as $$ select private.get_my_question_bank_overview(); $$;
revoke all on function public.get_my_question_bank_overview() from public,anon;
grant execute on function public.get_my_question_bank_overview() to authenticated,service_role;
;
