create or replace function public.review_question_slice_v18(p_slice_id bigint, p_decisions jsonb)
returns jsonb
language sql
security definer
set search_path to ''
as $function$
  select private.review_question_slice_v18(p_slice_id,p_decisions);
$function$;

revoke all on function public.review_question_slice_v18(bigint,jsonb) from public, anon;
grant execute on function public.review_question_slice_v18(bigint,jsonb) to authenticated, service_role;
