-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815165223
create or replace function private.start_mela_filtered_question_session_v18(
  p_program_key text,
  p_chapter_id uuid default null,
  p_topic_id uuid default null,
  p_count integer default 10,
  p_difficulty integer default null,
  p_practice_mode text default 'mastery'
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_count int := greatest(5,least(coalesce(p_count,10),30));
  v_ids uuid[] := '{}';
  v_session uuid;
  v_allow_sub boolean := false;
  v_allow_one boolean := false;
  v_mult numeric := 1.0;
  v_chapter_title text;
  v_topic_title text;
  v_available integer := 0;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if p_practice_mode not in ('mastery','supplemental') then raise exception 'practice mode must be mastery or supplemental'; end if;
  if not exists(select 1 from public.mela_learning_programs where program_key=p_program_key and active and program_kind='school_subject') then raise exception 'learning program not found'; end if;
  if (select count(*) from public.mela_question_sessions where user_id=v_uid and started_at>now()-interval '1 hour') >= 60 then raise exception 'question session rate limit reached'; end if;
  if p_difficulty is not null and (p_difficulty<1 or p_difficulty>5) then raise exception 'difficulty must be 1-5'; end if;
  if p_topic_id is not null then
    select c.title,t.title into v_chapter_title,v_topic_title
    from public.mela_learning_chapter_topics t join public.mela_learning_chapters c on c.id=t.chapter_id
    where t.id=p_topic_id and c.program_key=p_program_key and t.status='published' and c.status='published';
    if not found then raise exception 'topic not found in selected subject'; end if;
    if p_chapter_id is not null and not exists(select 1 from public.mela_learning_chapter_topics where id=p_topic_id and chapter_id=p_chapter_id) then raise exception 'topic does not belong to selected chapter'; end if;
  elsif p_chapter_id is not null then
    select title into v_chapter_title from public.mela_learning_chapters where id=p_chapter_id and program_key=p_program_key and status='published';
    if not found then raise exception 'chapter not found in selected subject'; end if;
  end if;
  v_allow_sub := private.mela_user_has_question_access(v_uid,'subscription');
  v_allow_one := private.mela_user_has_question_access(v_uid,'one_time');
  select coalesce(extended_time_multiplier,1.0) into v_mult from public.learner_accessibility_preferences where user_id=v_uid;
  v_mult := coalesce(v_mult,1.0);

  select count(*)::int into v_available
  from public.mela_question_bank q
  where q.program_key=p_program_key and q.active
    and (p_chapter_id is null or q.chapter_id=p_chapter_id)
    and (p_topic_id is null or q.topic_id=p_topic_id)
    and (p_difficulty is null or q.difficulty=p_difficulty)
    and ((p_practice_mode='mastery' and q.validation_status in ('deterministic_validated','educator_verified'))
      or (p_practice_mode='supplemental' and q.validation_status='review_required'))
    and (q.access_tier='free' or (q.access_tier='subscription' and v_allow_sub) or (q.access_tier='one_time' and v_allow_one));

  if v_available < 5 then
    if p_practice_mode='mastery' then
      raise exception 'mastery rebuild in progress for this filter: only % accessible mastery questions are currently available',v_available;
    else
      raise exception 'not enough accessible supplemental questions for this filter';
    end if;
  end if;

  select coalesce(array_agg(id order by sort_key),'{}'::uuid[]) into v_ids
  from (
    select q.id,hashtextextended(q.id::text||v_uid::text||clock_timestamp()::date::text,0) sort_key
    from public.mela_question_bank q
    where q.program_key=p_program_key and q.active
      and (p_chapter_id is null or q.chapter_id=p_chapter_id)
      and (p_topic_id is null or q.topic_id=p_topic_id)
      and (p_difficulty is null or q.difficulty=p_difficulty)
      and ((p_practice_mode='mastery' and q.validation_status in ('deterministic_validated','educator_verified'))
        or (p_practice_mode='supplemental' and q.validation_status='review_required'))
      and (q.access_tier='free' or (q.access_tier='subscription' and v_allow_sub) or (q.access_tier='one_time' and v_allow_one))
    order by sort_key limit v_count
  ) s;

  insert into public.mela_question_sessions(user_id,program_key,question_ids,requested_count,difficulty,seed,expires_at)
  values(v_uid,p_program_key,v_ids,cardinality(v_ids)::smallint,p_difficulty,concat(p_practice_mode,':',coalesce(p_topic_id::text,p_chapter_id::text,'subject')),now()+(interval '2 hours'*v_mult)) returning id into v_session;

  return jsonb_build_object(
    'session_id',v_session,'program_key',p_program_key,'practice_mode',p_practice_mode,'quality_state',case when p_practice_mode='mastery' then 'mastery_candidate' else 'supplemental_review_required' end,'available_count',v_available,
    'chapter_id',p_chapter_id,'chapter_title',v_chapter_title,'topic_id',p_topic_id,'topic_title',v_topic_title,
    'expires_at',(select expires_at from public.mela_question_sessions where id=v_session),
    'access',jsonb_build_object('subscription',v_allow_sub,'one_time',v_allow_one),
    'accessibility',coalesce((select to_jsonb(a)-'user_id'-'preference_note'-'created_at'-'updated_at' from public.learner_accessibility_preferences a where a.user_id=v_uid),'{}'::jsonb),
    'questions',(select jsonb_agg(jsonb_build_object('id',q.id,'question_number',q.question_number,'question_type',q.question_type,'prompt',q.prompt,'choices',q.choices,'difficulty',q.difficulty,'cognitive_level',q.cognitive_level,'access_tier',q.access_tier,'narration_text',q.narration_text,'response_schema',q.response_schema,'estimated_seconds',round(q.estimated_seconds*v_mult),'accessibility_support',q.accessibility_support,'quality_state',case when q.validation_status in ('deterministic_validated','educator_verified') then 'mastery_candidate' else 'supplemental_review_required' end) order by array_position(v_ids,q.id)) from public.mela_question_bank q where q.id=any(v_ids))
  );
end $$;

create or replace function public.start_mela_filtered_question_session_v18(p_program_key text,p_chapter_id uuid default null,p_topic_id uuid default null,p_count integer default 10,p_difficulty integer default null,p_practice_mode text default 'mastery') returns jsonb language sql set search_path='' as $$ select private.start_mela_filtered_question_session_v18(p_program_key,p_chapter_id,p_topic_id,p_count,p_difficulty,p_practice_mode); $$;
revoke all on function public.start_mela_filtered_question_session_v18(text,uuid,uuid,integer,integer,text) from public,anon;
grant execute on function public.start_mela_filtered_question_session_v18(text,uuid,uuid,integer,integer,text) to authenticated;

create or replace function public.get_question_catalog_v18(p_grade_level smallint default null) returns jsonb
language plpgsql stable set search_path=''
as $$ declare v_uid uuid:=(select auth.uid()); begin
 if v_uid is null then raise exception 'authentication required'; end if;
 return jsonb_build_object('quality_policy',jsonb_build_object('mastery_target_per_program',500,'mastery_counts_only',true,'supplemental_separate',true),'grades',coalesce((
 select jsonb_agg(jsonb_build_object('grade_level',g.grade_level,'inventory_questions',g.inventory_questions,'mastery_candidates',g.mastery_candidates,'supplemental_review_required',g.supplemental_review_required,'subjects',g.subjects) order by g.grade_level)
 from (
   select p.grade_level,sum(x.n)::bigint inventory_questions,sum(x.mastery_n)::bigint mastery_candidates,sum(x.review_n)::bigint supplemental_review_required,
   jsonb_agg(jsonb_build_object('program_key',p.program_key,'track_key',p.track_key,'subject_key',p.subject_key,'subject_title',p.subject_title,'inventory_count',x.n,'mastery_count',x.mastery_n,'supplemental_count',x.review_n,'mastery_gap_to_500',greatest(500-x.mastery_n,0),'free_mastery_count',x.free_mastery,'paid_mastery_count',x.paid_mastery,'chapter_count',(select count(*) from public.mela_learning_chapters c where c.program_key=p.program_key and c.status='published'),'topic_count',(select count(*) from public.mela_learning_chapter_topics t join public.mela_learning_chapters c2 on c2.id=t.chapter_id where c2.program_key=p.program_key and t.status='published')) order by p.display_order,p.subject_title,p.track_key) subjects
   from public.mela_learning_programs p
   join lateral (
     select count(*) n,
       count(*) filter(where q.validation_status in ('deterministic_validated','educator_verified')) mastery_n,
       count(*) filter(where q.validation_status='review_required') review_n,
       count(*) filter(where q.validation_status in ('deterministic_validated','educator_verified') and q.access_tier='free') free_mastery,
       count(*) filter(where q.validation_status in ('deterministic_validated','educator_verified') and q.access_tier in ('subscription','one_time')) paid_mastery
     from public.mela_question_bank q where q.program_key=p.program_key and q.active
   ) x on true
   where p.program_kind='school_subject' and p.grade_level between 1 and 12 and p.active and (p_grade_level is null or p.grade_level=p_grade_level)
   group by p.grade_level
 ) g),'[]'::jsonb));
end $$;
revoke all on function public.get_question_catalog_v18(smallint) from public,anon;
grant execute on function public.get_question_catalog_v18(smallint) to authenticated;

create or replace function public.get_question_subject_detail_v18(p_program_key text) returns jsonb
language plpgsql stable set search_path=''
as $$ declare v_uid uuid:=(select auth.uid()); v_program public.mela_learning_programs%rowtype; begin
 if v_uid is null then raise exception 'authentication required'; end if;
 select * into v_program from public.mela_learning_programs where program_key=p_program_key and active and program_kind='school_subject' and grade_level between 1 and 12;
 if not found then raise exception 'program not found'; end if;
 return jsonb_build_object('program',jsonb_build_object('program_key',v_program.program_key,'grade_level',v_program.grade_level,'track_key',v_program.track_key,'subject_key',v_program.subject_key,'subject_title',v_program.subject_title),'quality_policy',jsonb_build_object('mastery_target',500,'topic_minimum_to_start',5),'chapters',coalesce((
   select jsonb_agg(jsonb_build_object('chapter_id',c.id,'chapter_number',c.chapter_number,'chapter_title',c.title,'inventory_count',coalesce(qc.n,0),'mastery_count',coalesce(qc.mastery_n,0),'supplemental_count',coalesce(qc.review_n,0),'mastery_practice_available',coalesce(qc.mastery_n,0)>=5,'topics',coalesce((select jsonb_agg(jsonb_build_object('topic_id',t.id,'topic_number',t.topic_number,'topic_title',t.title,'inventory_count',coalesce(tq.n,0),'mastery_count',coalesce(tq.mastery_n,0),'supplemental_count',coalesce(tq.review_n,0),'mastery_practice_available',coalesce(tq.mastery_n,0)>=5) order by t.display_order,t.topic_number) from public.mela_learning_chapter_topics t left join lateral (select count(*) n,count(*) filter(where q.validation_status in ('deterministic_validated','educator_verified')) mastery_n,count(*) filter(where q.validation_status='review_required') review_n from public.mela_question_bank q where q.topic_id=t.id and q.active) tq on true where t.chapter_id=c.id and t.status='published'),'[]'::jsonb)) order by c.display_order,c.chapter_number)
   from public.mela_learning_chapters c left join lateral (select count(*) n,count(*) filter(where q.validation_status in ('deterministic_validated','educator_verified')) mastery_n,count(*) filter(where q.validation_status='review_required') review_n from public.mela_question_bank q where q.chapter_id=c.id and q.active) qc on true
   where c.program_key=p_program_key and c.status='published'),'[]'::jsonb));
end $$;
revoke all on function public.get_question_subject_detail_v18(text) from public,anon;
grant execute on function public.get_question_subject_detail_v18(text) to authenticated;
;
