-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815102936
create or replace function private.start_mela_question_session_v12(p_program_key text,p_count integer default 20,p_difficulty integer default null)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_count int := greatest(5,least(coalesce(p_count,20),30));
  v_start int;
  v_ids uuid[] := '{}';
  v_more uuid[] := '{}';
  v_session uuid;
  v_allow_sub boolean := false;
  v_allow_one boolean := false;
  v_mult numeric := 1.0;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if not exists(select 1 from public.mela_learning_programs where program_key=p_program_key and active) then raise exception 'learning program not found'; end if;
  if (select count(*) from public.mela_question_sessions where user_id=v_uid and started_at>now()-interval '1 hour') >= 60 then raise exception 'question session rate limit reached'; end if;
  if p_difficulty is not null and (p_difficulty<1 or p_difficulty>5) then raise exception 'difficulty must be 1-5'; end if;

  v_allow_sub := private.mela_user_has_question_access(v_uid,'subscription');
  v_allow_one := private.mela_user_has_question_access(v_uid,'one_time');
  select coalesce(extended_time_multiplier,1.0) into v_mult from public.learner_accessibility_preferences where user_id=v_uid;
  v_mult := coalesce(v_mult,1.0);
  v_start := 1 + mod(abs(hashtextextended(v_uid::text||p_program_key||clock_timestamp()::text,0))::bigint,800)::int;

  select coalesce(array_agg(id order by question_number),'{}'::uuid[]) into v_ids
  from (select id,question_number from public.mela_question_bank
        where program_key=p_program_key and active and question_number>=v_start
          and (p_difficulty is null or difficulty=p_difficulty)
          and (access_tier='free' or (access_tier='subscription' and v_allow_sub) or (access_tier='one_time' and v_allow_one))
        order by question_number limit v_count) a;

  if cardinality(v_ids)<v_count then
    select coalesce(array_agg(id order by question_number),'{}'::uuid[]) into v_more
    from (select id,question_number from public.mela_question_bank
          where program_key=p_program_key and active and question_number<v_start
            and (p_difficulty is null or difficulty=p_difficulty)
            and (access_tier='free' or (access_tier='subscription' and v_allow_sub) or (access_tier='one_time' and v_allow_one))
          order by question_number limit (v_count-cardinality(v_ids))) b;
    v_ids := v_ids || v_more;
  end if;
  if cardinality(v_ids)<5 then raise exception 'not enough accessible questions for this filter'; end if;

  insert into public.mela_question_sessions(user_id,program_key,question_ids,requested_count,difficulty,seed,expires_at)
  values(v_uid,p_program_key,v_ids,cardinality(v_ids)::smallint,p_difficulty,v_start::text,now()+(interval '2 hours'*v_mult)) returning id into v_session;

  return jsonb_build_object(
    'session_id',v_session,
    'program_key',p_program_key,
    'expires_at',(select expires_at from public.mela_question_sessions where id=v_session),
    'access',jsonb_build_object('subscription',v_allow_sub,'one_time',v_allow_one),
    'accessibility',coalesce((select to_jsonb(a)-'user_id'-'preference_note'-'created_at'-'updated_at' from public.learner_accessibility_preferences a where a.user_id=v_uid),'{}'::jsonb),
    'questions',(select jsonb_agg(jsonb_build_object(
      'id',q.id,'question_number',q.question_number,'question_type',q.question_type,'prompt',q.prompt,'choices',q.choices,
      'difficulty',q.difficulty,'cognitive_level',q.cognitive_level,'access_tier',q.access_tier,'narration_text',q.narration_text,
      'response_schema',q.response_schema,'estimated_seconds',round(q.estimated_seconds*v_mult),'accessibility_support',q.accessibility_support
    ) order by array_position(v_ids,q.id)) from public.mela_question_bank q where q.id=any(v_ids))
  );
end;
$$;
revoke all on function private.start_mela_question_session_v12(text,integer,integer) from public,anon,authenticated;
grant execute on function private.start_mela_question_session_v12(text,integer,integer) to authenticated,service_role;

create or replace function private.submit_mela_question_session_v12(p_session_id uuid,p_answers jsonb)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
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
    select q.id,q.question_number,q.question_type,q.prompt,g.grading_kind,g.correct_response,g.accepted_variants,g.tolerance,g.rationale
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
        v_ok := lower(trim(coalesce(case when jsonb_typeof(v_resp)='string' then trim(both '"' from v_resp::text) else v_resp->>'choice' end,''))) = lower(trim(r.correct_response->>'choice'));
      elsif r.grading_kind='multi_select' then
        v_ok := (select coalesce(array_agg(lower(value) order by lower(value)),'{}'::text[]) from jsonb_array_elements_text(case when jsonb_typeof(v_resp)='array' then v_resp else coalesce(v_resp->'choices','[]'::jsonb) end))
                = (select coalesce(array_agg(lower(value) order by lower(value)),'{}'::text[]) from jsonb_array_elements_text(r.correct_response->'choices'));
      elsif r.grading_kind='numeric' then
        begin
          v_ok := abs((case when jsonb_typeof(v_resp)='number' then v_resp::text::numeric else trim(both '"' from v_resp::text)::numeric end) - (r.correct_response->>'value')::numeric) <= coalesce(r.tolerance,0);
        exception when others then v_ok:=false; end;
      elsif r.grading_kind='short_answer' then
        v_norm := lower(regexp_replace(trim(case when jsonb_typeof(v_resp)='string' then trim(both '"' from v_resp::text) else coalesce(v_resp->>'text','') end),'[^[:alnum:] ]','','g'));
        v_ok := v_norm = lower(regexp_replace(trim(r.correct_response->>'text'),'[^[:alnum:] ]','','g')) or exists(select 1 from jsonb_array_elements_text(r.accepted_variants) x where v_norm=lower(regexp_replace(trim(x),'[^[:alnum:] ]','','g')));
      elsif r.grading_kind='matching' then
        v_ok := coalesce(case when jsonb_typeof(v_resp)='array' then v_resp else v_resp->'pairs' end,'[]'::jsonb) = r.correct_response->'pairs';
      elsif r.grading_kind='ordering' then
        v_ok := coalesce(case when jsonb_typeof(v_resp)='array' then v_resp else v_resp->'order' end,'[]'::jsonb) = r.correct_response->'order';
      else v_ok:=false;
      end if;
    end if;
    if v_ok then v_correct:=v_correct+1; end if;
    v_details := v_details || jsonb_build_array(jsonb_build_object('question_id',r.id,'question_number',r.question_number,'question_type',r.question_type,'correct',v_ok,'correct_response',r.correct_response,'rationale',r.rationale));
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
$$;
revoke all on function private.submit_mela_question_session_v12(uuid,jsonb) from public,anon,authenticated;
grant execute on function private.submit_mela_question_session_v12(uuid,jsonb) to authenticated,service_role;

create or replace function public.start_mela_question_session_v12(p_program_key text,p_count integer default 20,p_difficulty integer default null)
returns jsonb language sql security invoker set search_path='' as $$ select private.start_mela_question_session_v12(p_program_key,p_count,p_difficulty); $$;
revoke all on function public.start_mela_question_session_v12(text,integer,integer) from public,anon;
grant execute on function public.start_mela_question_session_v12(text,integer,integer) to authenticated,service_role;

create or replace function public.submit_mela_question_session_v12(p_session_id uuid,p_answers jsonb)
returns jsonb language sql security invoker set search_path='' as $$ select private.submit_mela_question_session_v12(p_session_id,p_answers); $$;
revoke all on function public.submit_mela_question_session_v12(uuid,jsonb) from public,anon;
grant execute on function public.submit_mela_question_session_v12(uuid,jsonb) to authenticated,service_role;

create or replace function public.get_my_question_bank_overview_v12()
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare v_uid uuid:=(select auth.uid()); begin
 if v_uid is null then raise exception 'authentication required'; end if;
 return jsonb_build_object(
  'programs',coalesce((select jsonb_agg(jsonb_build_object('program_key',p.program_key,'grade_level',p.grade_level,'track_key',p.track_key,'subject_title',p.subject_title,'question_count',x.n,'free_count',x.free_n,'subscription_count',x.sub_n,'paid_pack_count',x.one_n,'types',x.types,'stats',coalesce(to_jsonb(s)-'user_id'-'program_key'-'created_at'-'updated_at','{}'::jsonb)) order by p.grade_level,p.display_order,p.subject_title)
   from public.mela_learning_programs p
   join lateral (select count(*) n,count(*) filter(where q.access_tier='free') free_n,count(*) filter(where q.access_tier='subscription') sub_n,count(*) filter(where q.access_tier='one_time') one_n,jsonb_object_agg(q.question_type,q.cnt) types from (select program_key,access_tier,question_type,count(*) cnt from public.mela_question_bank where program_key=p.program_key and active group by program_key,access_tier,question_type) q) x on true
   left join public.mela_question_user_program_stats s on s.program_key=p.program_key and s.user_id=v_uid
   where p.program_kind='school_subject' and p.grade_level between 1 and 12 and p.active),'[]'::jsonb),
  'accessibility',coalesce((select to_jsonb(a)-'user_id'-'preference_note'-'created_at'-'updated_at' from public.learner_accessibility_preferences a where a.user_id=v_uid),'{}'::jsonb)
 );
end; $$;
revoke all on function public.get_my_question_bank_overview_v12() from public,anon;
grant execute on function public.get_my_question_bank_overview_v12() to authenticated,service_role;
;
