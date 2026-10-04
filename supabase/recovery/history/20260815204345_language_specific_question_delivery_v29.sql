-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815204345
alter table public.mela_question_bank add column if not exists content_language_code text;
alter table public.mela_question_bank drop constraint if exists mela_question_bank_content_language_code_check;
alter table public.mela_question_bank add constraint mela_question_bank_content_language_code_check check (content_language_code is null or content_language_code ~ '^[a-z]{2,3}(-[A-Z]{2})?$');

create index if not exists mela_question_bank_program_language_mastery_idx on public.mela_question_bank(program_key,content_language_code,validation_status,active) where active;

create or replace function private.start_mela_filtered_question_session_v18(p_program_key text, p_chapter_id uuid default null, p_topic_id uuid default null, p_count integer default 10, p_difficulty integer default null, p_practice_mode text default 'mastery')
returns jsonb
language plpgsql
security definer
set search_path=''
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
  v_subject text;
  v_pref text;
  v_content_lang text := null;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if p_practice_mode not in ('mastery','supplemental') then raise exception 'practice mode must be mastery or supplemental'; end if;
  select subject_title into v_subject from public.mela_learning_programs where program_key=p_program_key and active and program_kind='school_subject';
  if v_subject is null then raise exception 'learning program not found'; end if;
  if (select count(*) from public.mela_question_sessions where user_id=v_uid and started_at>now()-interval '1 hour') >= 60 then raise exception 'question session rate limit reached'; end if;
  if p_difficulty is not null and (p_difficulty<1 or p_difficulty>5) then raise exception 'difficulty must be 1-5'; end if;

  select preferred_language into v_pref from public.profiles where id=v_uid;
  if v_subject='Native Language' then
    v_content_lang := case v_pref when 'Amharic' then 'am' when 'Afaan Oromo' then 'om' when 'Tigrinya' then 'ti' when 'Somali' then 'so' else null end;
    if v_content_lang is null then raise exception 'Choose Amharic, Afaan Oromo, Tigrinya, or Somali in Mela before starting Native Language practice'; end if;
  elsif v_subject='Federal Working Language' then
    v_content_lang := 'am';
  elsif v_subject='Foreign Language' then
    raise exception 'Foreign Language is optional and requires a verified school/curriculum language variant before mastery practice';
  end if;

  if p_topic_id is not null then
    select c.title,t.title into v_chapter_title,v_topic_title from public.mela_learning_chapter_topics t join public.mela_learning_chapters c on c.id=t.chapter_id where t.id=p_topic_id and c.program_key=p_program_key and t.status='published' and c.status='published';
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

  select count(*)::int into v_available from public.mela_question_bank q
  where q.program_key=p_program_key and q.active
    and (v_content_lang is null or q.content_language_code=v_content_lang)
    and (p_chapter_id is null or q.chapter_id=p_chapter_id)
    and (p_topic_id is null or q.topic_id=p_topic_id)
    and (p_difficulty is null or q.difficulty=p_difficulty)
    and ((p_practice_mode='mastery' and q.validation_status in ('deterministic_validated','educator_verified')) or (p_practice_mode='supplemental' and q.validation_status='review_required'))
    and (q.access_tier='free' or (q.access_tier='subscription' and v_allow_sub) or (q.access_tier='one_time' and v_allow_one));

  if v_available < 5 then
    if p_practice_mode='mastery' then raise exception 'mastery rebuild in progress for this filter: only % accessible mastery questions are currently available',v_available;
    else raise exception 'not enough accessible supplemental questions for this filter'; end if;
  end if;

  select coalesce(array_agg(id order by sort_key),'{}'::uuid[]) into v_ids from (
    select q.id,hashtextextended(q.id::text||v_uid::text||clock_timestamp()::date::text,0) sort_key
    from public.mela_question_bank q
    where q.program_key=p_program_key and q.active
      and (v_content_lang is null or q.content_language_code=v_content_lang)
      and (p_chapter_id is null or q.chapter_id=p_chapter_id)
      and (p_topic_id is null or q.topic_id=p_topic_id)
      and (p_difficulty is null or q.difficulty=p_difficulty)
      and ((p_practice_mode='mastery' and q.validation_status in ('deterministic_validated','educator_verified')) or (p_practice_mode='supplemental' and q.validation_status='review_required'))
      and (q.access_tier='free' or (q.access_tier='subscription' and v_allow_sub) or (q.access_tier='one_time' and v_allow_one))
    order by sort_key limit v_count
  ) s;

  insert into public.mela_question_sessions(user_id,program_key,question_ids,requested_count,difficulty,seed,expires_at)
  values(v_uid,p_program_key,v_ids,cardinality(v_ids)::smallint,p_difficulty,concat(p_practice_mode,':',coalesce(p_topic_id::text,p_chapter_id::text,'subject'),':',coalesce(v_content_lang,'ui')),now()+(interval '2 hours'*v_mult)) returning id into v_session;

  return jsonb_build_object(
    'session_id',v_session,'program_key',p_program_key,'practice_mode',p_practice_mode,'quality_state',case when p_practice_mode='mastery' then 'mastery_candidate' else 'supplemental_review_required' end,'available_count',v_available,'content_language_code',v_content_lang,
    'chapter_id',p_chapter_id,'chapter_title',v_chapter_title,'topic_id',p_topic_id,'topic_title',v_topic_title,'expires_at',(select expires_at from public.mela_question_sessions where id=v_session),
    'access',jsonb_build_object('subscription',v_allow_sub,'one_time',v_allow_one),'accessibility',coalesce((select to_jsonb(a)-'user_id'-'preference_note'-'created_at'-'updated_at' from public.learner_accessibility_preferences a where a.user_id=v_uid),'{}'::jsonb),
    'questions',(select jsonb_agg(jsonb_build_object('id',q.id,'question_number',q.question_number,'question_type',q.question_type,'prompt',q.prompt,'choices',q.choices,'difficulty',q.difficulty,'cognitive_level',q.cognitive_level,'access_tier',q.access_tier,'narration_text',q.narration_text,'response_schema',q.response_schema,'estimated_seconds',round(q.estimated_seconds*v_mult),'accessibility_support',q.accessibility_support,'content_language_code',q.content_language_code,'quality_state',case when q.validation_status in ('deterministic_validated','educator_verified') then 'mastery_candidate' else 'supplemental_review_required' end) order by array_position(v_ids,q.id)) from public.mela_question_bank q where q.id=any(v_ids))
  );
end $$;

revoke all on function private.start_mela_filtered_question_session_v18(text,uuid,uuid,integer,integer,text) from public,anon;
grant execute on function private.start_mela_filtered_question_session_v18(text,uuid,uuid,integer,integer,text) to authenticated,service_role;
;
