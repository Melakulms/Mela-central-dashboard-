-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260818171333
create or replace function public.service_get_mela_question_answer_key(p_question_id uuid)
returns jsonb
language sql
security definer
set search_path = 'pg_catalog', 'private'
as $function$
  select case
    when k.question_id is null then null
    else jsonb_build_object(
      'question_id', k.question_id,
      'correct_choice', k.correct_choice,
      'correct_text', k.correct_text,
      'explanation', k.explanation,
      'validation_method', k.validation_method
    )
  end
  from (select p_question_id as requested_id) q
  left join private.mela_question_answer_keys k on k.question_id = q.requested_id;
$function$;

revoke all on function public.service_get_mela_question_answer_key(uuid) from public, anon, authenticated;
grant execute on function public.service_get_mela_question_answer_key(uuid) to service_role;
;
