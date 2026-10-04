-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260813081805
create or replace function public.admin_get_assessment_answer_key(p_question_id uuid)
returns jsonb
language sql
security definer
set search_path='pg_catalog','private'
as $function$
  select case when k.question_id is null then null else jsonb_build_object('question_id',k.question_id,'correct_answer',k.correct_answer,'explanation',k.explanation,'updated_at',k.updated_at) end
  from (select p_question_id as requested_id) q
  left join private.assessment_answer_keys k on k.question_id=q.requested_id;
$function$;
revoke all on function public.admin_get_assessment_answer_key(uuid) from public, anon, authenticated;
grant execute on function public.admin_get_assessment_answer_key(uuid) to service_role;

create or replace function public.admin_set_assessment_answer_key(p_question_id uuid,p_correct_answer jsonb,p_explanation text default null)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','private','public'
as $function$
begin
  if not exists(select 1 from public.assessment_questions where id=p_question_id) then
    raise exception 'Assessment question not found';
  end if;
  insert into private.assessment_answer_keys(question_id,correct_answer,explanation,updated_at)
  values(p_question_id,p_correct_answer,p_explanation,now())
  on conflict(question_id) do update set correct_answer=excluded.correct_answer, explanation=excluded.explanation, updated_at=now();
  return jsonb_build_object('question_id',p_question_id,'saved',true);
end;
$function$;
revoke all on function public.admin_set_assessment_answer_key(uuid,jsonb,text) from public, anon, authenticated;
grant execute on function public.admin_set_assessment_answer_key(uuid,jsonb,text) to service_role;

create or replace function public.admin_get_practice_answer_key(p_question_id uuid)
returns jsonb
language sql
security definer
set search_path='pg_catalog','private'
as $function$
  select case when k.question_id is null then null else jsonb_build_object('question_id',k.question_id,'correct_answer',k.correct_answer,'rubric',k.rubric,'explanation',k.explanation,'auto_gradable',k.auto_gradable,'updated_at',k.updated_at) end
  from (select p_question_id as requested_id) q
  left join private.practice_answer_keys k on k.question_id=q.requested_id;
$function$;
revoke all on function public.admin_get_practice_answer_key(uuid) from public, anon, authenticated;
grant execute on function public.admin_get_practice_answer_key(uuid) to service_role;

create or replace function public.admin_set_practice_answer_key(p_question_id uuid,p_correct_answer jsonb,p_rubric jsonb default '{}'::jsonb,p_explanation text default null,p_auto_gradable boolean default true)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','private','public'
as $function$
begin
  if not exists(select 1 from public.practice_questions where id=p_question_id) then
    raise exception 'Practice question not found';
  end if;
  insert into private.practice_answer_keys(question_id,correct_answer,rubric,explanation,auto_gradable,created_at,updated_at)
  values(p_question_id,p_correct_answer,coalesce(p_rubric,'{}'::jsonb),p_explanation,p_auto_gradable,now(),now())
  on conflict(question_id) do update set correct_answer=excluded.correct_answer,rubric=excluded.rubric,explanation=excluded.explanation,auto_gradable=excluded.auto_gradable,updated_at=now();
  return jsonb_build_object('question_id',p_question_id,'saved',true);
end;
$function$;
revoke all on function public.admin_set_practice_answer_key(uuid,jsonb,jsonb,text,boolean) from public, anon, authenticated;
grant execute on function public.admin_set_practice_answer_key(uuid,jsonb,jsonb,text,boolean) to service_role;
;
