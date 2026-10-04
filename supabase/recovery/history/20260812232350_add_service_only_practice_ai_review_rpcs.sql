-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812232350
grant usage on schema private to service_role;
grant select on private.practice_answer_keys to service_role;

create or replace function public.get_practice_review_context(p_user_id uuid,p_session_id uuid,p_question_id uuid)
returns jsonb language sql stable security invoker set search_path='' as $$
select jsonb_build_object(
  'session_id',s.id,
  'question_id',q.id,
  'question',q.question,
  'question_type',q.question_type,
  'max_points',a.max_points,
  'response',a.response,
  'attachment_path',a.attachment_path,
  'rubric',k.rubric,
  'guidance',k.explanation,
  'topic',t.topic,
  'subject',t.subject
)
from public.practice_sessions s
join public.practice_attempts a on a.session_id=s.id and a.user_id=s.user_id
join public.practice_questions q on q.id=a.question_id
join public.practice_topics t on t.id=q.topic_id
join private.practice_answer_keys k on k.question_id=q.id
where s.id=p_session_id and s.user_id=p_user_id and q.id=p_question_id and k.auto_gradable=false;
$$;

create or replace function public.record_practice_ai_review(p_user_id uuid,p_session_id uuid,p_question_id uuid,p_score numeric,p_feedback text)
returns void language plpgsql security invoker set search_path='' as $$
declare v_max numeric;
begin
  select a.max_points into v_max
  from public.practice_attempts a join public.practice_sessions s on s.id=a.session_id
  where a.session_id=p_session_id and a.question_id=p_question_id and a.user_id=p_user_id and s.user_id=p_user_id;
  if v_max is null then raise exception 'Practice response not found'; end if;
  if p_score<0 or p_score>v_max then raise exception 'Score outside allowed range'; end if;
  update public.practice_attempts set score=p_score,feedback=left(coalesce(p_feedback,''),4000),reviewed_at=now()
  where session_id=p_session_id and question_id=p_question_id and user_id=p_user_id;
end $$;

revoke all on function public.get_practice_review_context(uuid,uuid,uuid) from public,anon,authenticated;
revoke all on function public.record_practice_ai_review(uuid,uuid,uuid,numeric,text) from public,anon,authenticated;
grant execute on function public.get_practice_review_context(uuid,uuid,uuid) to service_role;
grant execute on function public.record_practice_ai_review(uuid,uuid,uuid,numeric,text) to service_role;
;
