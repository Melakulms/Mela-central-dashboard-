-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260907083627
create or replace function public.submit_mela_question_session_v12(p_session_id uuid, p_answers jsonb)
returns jsonb
language sql
security definer
set search_path to ''
as $function$
  select private.submit_mela_question_session_v12(p_session_id,p_answers)
$function$;

create or replace function private.submit_mela_question_session_v12(p_session_id uuid, p_answers jsonb)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_session public.mela_question_sessions%rowtype;
  v_answered int:=0;
  v_correct int:=0;
  v_score numeric:=0;
  v_details jsonb:='[]'::jsonb;
  r record;
  v_resp jsonb;
  v_ok boolean;
  v_norm text;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if jsonb_typeof(p_answers)<>'array' then raise exception 'answers must be a JSON array'; end if;
  select * into v_session from public.mela_question_sessions where id=p_session_id and user_id=v_uid for update;
  if not found then raise exception 'question session not found'; end if;
  if v_session.status<>'started' then raise exception 'question session already submitted'; end if;
  if v_session.expires_at<now() then raise exception 'question session expired'; end if;

  for r in
    select q.id,q.question_number,q.question_type,g.grading_kind,g.correct_response,g.accepted_variants,g.tolerance,g.rationale
    from public.mela_question_bank q join private.mela_question_grading_v12 g on g.question_id=q.id
    where q.id=any(v_session.question_ids)
    order by array_position(v_session.question_ids,q.id)
  loop
    select a->'response' into v_resp from jsonb_array_elements(p_answers) a where a->>'question_id'=r.id::text limit 1;
    if v_resp is null then
      v_ok:=false;
    else
      v_answered:=v_answered+1;
      if r.grading_kind in ('single_choice','true_false') then
        v_ok := lower(trim(coalesce(case when jsonb_typeof(v_resp)='string' then trim(both '\"' from v_resp::text) else v_resp->>'choice' end,''))) = lower(trim(r.correct_response->>'choice'));
      elsif r.grading_kind='multi_select' then
        v_ok := (select coalesce(array_agg(lower(value) order by lower(value)),'{}'::text[]) from jsonb_array_elements_text(case when jsonb_typeof(v_resp)='array' then v_resp else coalesce(v_resp->'choices','[]'::jsonb) end))
                = (select coalesce(array_agg(lower(value) order by lower(value)),'{}'::text[]) from jsonb_array_elements_text(r.correct_response->'choices'));
      elsif r.grading_kind='numeric' then
        begin
          v_ok := abs((case when jsonb_typeof(v_resp)='number' then v_resp::text::numeric else trim(both '\"' from v_resp::text)::numeric end) - (r.correct_response->>'value')::numeric) <= coalesce(r.tolerance,0);
        exception when others then v_ok:=false; end;
      elsif r.grading_kind='short_answer' then
        v_norm := lower(regexp_replace(trim(case when jsonb_typeof(v_resp)='string' then trim(both '\"' from v_resp::text) else coalesce(v_resp->>'text','') end),'[^[:alnum:] ]','','g'));
        v_ok := v_norm = lower(regexp_replace(trim(r.correct_response->>'text'),'[^[:alnum:] ]','','g')) or exists(select 1 from jsonb_array_elements_text(r.accepted_variants) x where v_norm=lower(regexp_replace(trim(x),'[^[:alnum:] ]','','g')));
      elsif r.grading_kind='matching' then
        v_ok := coalesce(case when jsonb_typeof(v_resp)='array' then v_resp else v_resp->'pairs' end,'[]'::jsonb) = r.correct_response->'pairs';
      elsif r.grading_kind='ordering' then
        v_ok := coalesce(case when jsonb_typeof(v_resp)='array' then v_resp else v_resp->'order' end,'[]'::jsonb) = r.correct_response->'order';
      else v_ok:=false;
      end if;
    end if;
    if v_ok then v_correct:=v_correct+1; end if;
    v_details := v_details || jsonb_build_array(jsonb_build_object('question_id',r.id,'question_number',r.question_number,'question_type',r.question_type,'correct',v_ok,'rationale',r.rationale));
  end loop;

  v_score := case when cardinality(v_session.question_ids)>0 then round(100.0*v_correct/cardinality(v_session.question_ids),2) else 0 end;
  update public.mela_question_sessions set status='submitted',selected_answers=p_answers,answered_count=v_answered::smallint,correct_count=v_correct::smallint,score_percent=v_score,submitted_at=now() where id=p_session_id;

  insert into public.mela_question_user_program_stats(user_id,program_key,sessions_completed,questions_answered,correct_answers,cumulative_score,average_score,best_score,last_score,last_practiced_at)
  values(v_uid,v_session.program_key,1,cardinality(v_session.question_ids),v_correct,v_score,v_score,v_score,v_score,now())
  on conflict(user_id,program_key) do update set
    sessions_completed=public.mela_question_user_program_stats.sessions_completed+1,
    questions_answered=public.mela_question_user_program_stats.questions_answered+excluded.questions_answered,
    correct_answers=public.mela_question_user_program_stats.correct_answers+excluded.correct_answers,
    cumulative_score=public.mela_question_user_program_stats.cumulative_score+excluded.cumulative_score,
    average_score=round((public.mela_question_user_program_stats.cumulative_score+excluded.cumulative_score)/(public.mela_question_user_program_stats.sessions_completed+1),2),
    best_score=greatest(coalesce(public.mela_question_user_program_stats.best_score,0),excluded.best_score),
    last_score=excluded.last_score,last_practiced_at=now(),updated_at=now();

  return jsonb_build_object('session_id',p_session_id,'answered_count',v_answered,'correct_count',v_correct,'question_count',cardinality(v_session.question_ids),'score_percent',v_score,'details',v_details);
end;
$function$;
;
