-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20261004041220
create or replace function public.can_review_questions_v18()
returns boolean
language sql
stable
security invoker
set search_path to ''
as $function$
  select private.can_review_questions_v18();
$function$;

revoke all on function private.can_review_questions_v18() from public, anon;
grant execute on function private.can_review_questions_v18() to authenticated, service_role;
revoke all on function public.can_review_questions_v18() from public, anon;
grant execute on function public.can_review_questions_v18() to authenticated, service_role;
;
