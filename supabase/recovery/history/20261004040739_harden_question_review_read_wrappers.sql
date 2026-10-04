-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20261004040739
create or replace function public.get_question_review_queue_v18(p_program_key text default null, p_limit integer default 50)
returns jsonb
language sql
stable
security invoker
set search_path to ''
as $function$
  select private.get_question_review_queue_v18(p_program_key,p_limit);
$function$;

create or replace function public.get_question_review_slice_v18(p_slice_id bigint)
returns jsonb
language sql
stable
security invoker
set search_path to ''
as $function$
  select private.get_question_review_slice_v18(p_slice_id);
$function$;

revoke all on function private.get_question_review_queue_v18(text,integer) from public, anon;
revoke all on function private.get_question_review_slice_v18(bigint) from public, anon;
grant execute on function private.get_question_review_queue_v18(text,integer) to authenticated, service_role;
grant execute on function private.get_question_review_slice_v18(bigint) to authenticated, service_role;

revoke all on function public.get_question_review_queue_v18(text,integer) from public, anon;
revoke all on function public.get_question_review_slice_v18(bigint) from public, anon;
grant execute on function public.get_question_review_queue_v18(text,integer) to authenticated, service_role;
grant execute on function public.get_question_review_slice_v18(bigint) to authenticated, service_role;
;
