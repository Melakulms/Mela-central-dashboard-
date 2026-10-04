-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815093313
create table if not exists public.mela_question_user_program_stats (
  user_id uuid not null references public.profiles(id) on delete cascade,
  program_key text not null references public.mela_learning_programs(program_key) on update cascade on delete cascade,
  sessions_completed bigint not null default 0,
  questions_answered bigint not null default 0,
  correct_answers bigint not null default 0,
  cumulative_score numeric(18,2) not null default 0,
  average_score numeric(5,2) not null default 0,
  best_score numeric(5,2),
  last_score numeric(5,2),
  last_practiced_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(user_id,program_key)
);
alter table public.mela_question_user_program_stats enable row level security;
revoke all on public.mela_question_user_program_stats from public,anon;
grant select on public.mela_question_user_program_stats to authenticated;
grant select,insert,update,delete on public.mela_question_user_program_stats to service_role;
drop policy if exists mela_question_stats_owner_read on public.mela_question_user_program_stats;
create policy mela_question_stats_owner_read on public.mela_question_user_program_stats
for select to authenticated using ((select auth.uid())=user_id);
create index if not exists mela_question_stats_program_idx on public.mela_question_user_program_stats(program_key,last_practiced_at desc);

create or replace function private.start_mela_question_session(
  p_program_key text,
  p_count integer default 20,
  p_difficulty smallint default null,
  p_seed text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_role text;
  v_stage text;
  v_grade smallint;
  v_admin boolean := false;
  v_program record;
  v_count integer := greatest(5,least(coalesce(p_count,20),30));
  v_seed text := coalesce(nullif(p_seed,''),coalesce(v_uid::text,'')||':'||current_date::text||':'||p_program_key);
  v_start integer;
  v_ids uuid[];
  v_session uuid;
  v_recent integer;
  v_questions jsonb;
  v_has_subscription boolean := false;
  v_has_one_time boolean := false;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select role,education_stage_key,grade_level into v_role,v_stage,v_grade from public.profiles where id=v_uid;
  v_admin := coalesce(v_role='admin',false);
  select program_key,stage_key,grade_level,track_key,subject_title into v_program from public.mela_learning_programs where program_key=p_program_key and active;
  if v_program.program_key is null then raise exception 'learning program not found'; end if;
  if not v_admin then
    if v_role<>'student' then raise exception 'learner access required'; end if;
    if v_program.stage_key<>v_stage then raise exception 'program is not available for your education stage'; end if;
    if v_program.grade_level is not null and v_program.grade_level<>v_grade then raise exception 'program is not available for your grade'; end if;
  end if;

  if v_admin then
    v_has_subscription:=true; v_has_one_time:=true;
  else
    select exists(
      select 1 from public.mela_user_learning_entitlements e
      where e.user_id=v_uid and e.status='active' and e.starts_at<=now() and (e.ends_at is null or e.ends_at>now())
        and e.product_key in ('school_plus_monthly','school_plus_annual','family_plus_monthly','institution_learning_license')
    ) into v_has_subscription;
    select exists(
      select 1 from public.mela_user_learning_entitlements e
      where e.user_id=v_uid and e.status='active' and e.starts_at<=now() and (e.ends_at is null or e.ends_at>now())
        and e.product_key in ('grade12_exam_master','institution_learning_license')
    ) into v_has_one_time;
  end if;

  select count(*) into v_recent from public.mela_question_sessions where user_id=v_uid and started_at>now()-interval '1 hour';
  if v_recent>=60 then raise exception 'question-session rate limit reached; try again later'; end if;

  select 1 + mod(abs(hashtextextended(v_seed,0)),greatest(count(*),1))::integer into v_start
  from public.mela_question_bank q
  where q.program_key=p_program_key and q.active
    and (p_difficulty is null or q.difficulty=p_difficulty)
    and (q.access_tier='free' or (q.access_tier='subscription' and v_has_subscription) or (q.access_tier='one_time' and v_has_one_time));

  with eligible as (
    select q.id,q.question_number,q.prompt,q.choices,q.difficulty,q.question_type,q.access_tier,q.validation_status,q.chapter_id,q.topic_id
    from public.mela_question_bank q
    where q.program_key=p_program_key and q.active
      and (p_difficulty is null or q.difficulty=p_difficulty)
      and (q.access_tier='free' or (q.access_tier='subscription' and v_has_subscription) or (q.access_tier='one_time' and v_has_one_time))
  ), picked as (
    (select * from eligible where question_number>=v_start order by question_number limit v_count)
    union all
    (select * from eligible where question_number<v_start order by question_number limit v_count)
  ), final_pick as (select * from picked limit v_count)
  select array_agg(id order by question_number),
         jsonb_agg(jsonb_build_object(
           'id',id,'question_number',question_number,'prompt',prompt,'choices',choices,'difficulty',difficulty,
           'question_type',question_type,'access_tier',access_tier,'validation_status',validation_status,
           'chapter_id',chapter_id,'topic_id',topic_id
         ) order by question_number)
  into v_ids,v_questions from final_pick;

  if coalesce(array_length(v_ids,1),0)<v_count then raise exception 'not enough accessible questions for this filter'; end if;
  insert into public.mela_question_sessions(user_id,program_key,question_ids,requested_count,difficulty,seed)
  values(v_uid,p_program_key,v_ids,v_count,p_difficulty,v_seed) returning id into v_session;
  return jsonb_build_object('session_id',v_session,'program_key',p_program_key,'subject_title',v_program.subject_title,'count',v_count,'questions',coalesce(v_questions,'[]'::jsonb),'answer_keys_exposed',false);
end;
$$;

create or replace function private.submit_mela_question_session(p_session_id uuid,p_answers jsonb)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_s record;
  v_answered integer;
  v_correct integer;
  v_total integer;
  v_score numeric(5,2);
  v_feedback jsonb;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select * into v_s from public.mela_question_sessions where id=p_session_id and user_id=v_uid for update;
  if v_s.id is null then raise exception 'question session not found'; end if;
  if v_s.status<>'started' then raise exception 'question session already submitted or expired'; end if;
  if v_s.expires_at<=now() then
    update public.mela_question_sessions set status='expired' where id=p_session_id;
    raise exception 'question session expired';
  end if;
  if jsonb_typeof(coalesce(p_answers,'[]'::jsonb))<>'array' then raise exception 'answers must be an array'; end if;
  if jsonb_array_length(coalesce(p_answers,'[]'::jsonb))>30 then raise exception 'too many answers'; end if;

  with supplied as (
    select (x->>'question_id')::uuid question_id,upper(trim(x->>'selected_choice')) selected_choice
    from jsonb_array_elements(coalesce(p_answers,'[]'::jsonb)) x
    where x ? 'question_id' and x ? 'selected_choice'
  ), valid as (
    select distinct on (s.question_id) s.question_id,s.selected_choice,a.correct_choice,a.correct_text,a.explanation,
           (s.selected_choice=a.correct_choice) is_correct
    from supplied s
    join private.mela_question_answer_keys a on a.question_id=s.question_id
    where s.question_id=any(v_s.question_ids) and s.selected_choice in ('A','B','C','D')
    order by s.question_id
  )
  select count(*),count(*) filter(where is_correct),
         coalesce(jsonb_agg(jsonb_build_object('question_id',question_id,'selected_choice',selected_choice,'correct_choice',correct_choice,'correct_text',correct_text,'is_correct',is_correct,'explanation',explanation)),'[]'::jsonb)
  into v_answered,v_correct,v_feedback from valid;
  v_total:=array_length(v_s.question_ids,1);
  v_score:=round((100.0*v_correct/greatest(v_total,1))::numeric,2);

  update public.mela_question_sessions
  set status='submitted',selected_answers=coalesce(p_answers,'[]'::jsonb),answered_count=v_answered,correct_count=v_correct,score_percent=v_score,submitted_at=now()
  where id=p_session_id;

  insert into public.mela_question_user_program_stats(user_id,program_key,sessions_completed,questions_answered,correct_answers,cumulative_score,average_score,best_score,last_score,last_practiced_at)
  values(v_uid,v_s.program_key,1,v_answered,v_correct,v_score,v_score,v_score,v_score,now())
  on conflict(user_id,program_key) do update set
    sessions_completed=public.mela_question_user_program_stats.sessions_completed+1,
    questions_answered=public.mela_question_user_program_stats.questions_answered+excluded.questions_answered,
    correct_answers=public.mela_question_user_program_stats.correct_answers+excluded.correct_answers,
    cumulative_score=public.mela_question_user_program_stats.cumulative_score+excluded.cumulative_score,
    average_score=round((public.mela_question_user_program_stats.cumulative_score+excluded.cumulative_score)/(public.mela_question_user_program_stats.sessions_completed+1),2),
    best_score=greatest(coalesce(public.mela_question_user_program_stats.best_score,excluded.last_score),excluded.last_score),
    last_score=excluded.last_score,last_practiced_at=excluded.last_practiced_at,updated_at=now();

  return jsonb_build_object('session_id',p_session_id,'answered',v_answered,'total',v_total,'correct',v_correct,'score_percent',v_score,'feedback',v_feedback);
end;
$$;

create or replace function private.get_my_question_bank_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_stage text;
  v_grade smallint;
  v_role text;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select education_stage_key,grade_level,role into v_stage,v_grade,v_role from public.profiles where id=v_uid;
  return jsonb_build_object(
    'stage_key',v_stage,'grade_level',v_grade,
    'programs',coalesce((
      select jsonb_agg(jsonb_build_object(
        'program_key',p.program_key,'subject_title',p.subject_title,'track_key',p.track_key,
        'question_count',(select count(*) from public.mela_question_bank q where q.program_key=p.program_key and q.active),
        'free_count',(select count(*) from public.mela_question_bank q where q.program_key=p.program_key and q.active and q.access_tier='free'),
        'subscription_count',(select count(*) from public.mela_question_bank q where q.program_key=p.program_key and q.active and q.access_tier='subscription'),
        'one_time_count',(select count(*) from public.mela_question_bank q where q.program_key=p.program_key and q.active and q.access_tier='one_time'),
        'educator_verified_count',(select count(*) from public.mela_question_bank q where q.program_key=p.program_key and q.active and q.validation_status='educator_verified'),
        'stats',(select to_jsonb(s) - 'user_id' from public.mela_question_user_program_stats s where s.user_id=v_uid and s.program_key=p.program_key)
      ) order by p.display_order,p.subject_title)
      from public.mela_learning_programs p
      where p.active and (v_role='admin' or (p.stage_key=v_stage and (p.grade_level is null or p.grade_level=v_grade)))
    ),'[]'::jsonb),
    'recent_sessions',coalesce((select jsonb_agg(to_jsonb(x) order by x.started_at desc) from (select id,program_key,status,requested_count,answered_count,correct_count,score_percent,started_at,submitted_at from public.mela_question_sessions where user_id=v_uid order by started_at desc limit 10) x),'[]'::jsonb)
  );
end;
$$;

select cron.unschedule(jobid) from cron.job where jobname='mela-question-session-retention';
select cron.schedule('mela-question-session-retention','31 3 * * *',
  $$delete from public.mela_question_sessions where status in ('submitted','expired') and coalesce(submitted_at,started_at)<now()-interval '90 days';$$
);
;
