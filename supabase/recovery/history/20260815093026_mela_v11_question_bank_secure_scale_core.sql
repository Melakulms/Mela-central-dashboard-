-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815093026
create table if not exists public.mela_question_bank (
  id uuid primary key default gen_random_uuid(),
  program_key text not null references public.mela_learning_programs(program_key) on update cascade on delete cascade,
  chapter_id uuid references public.mela_learning_chapters(id) on delete cascade,
  topic_id uuid references public.mela_learning_chapter_topics(id) on delete cascade,
  question_key text not null unique,
  question_number integer not null,
  question_type text not null check (question_type in ('single_choice','true_false')),
  prompt text not null,
  choices jsonb not null default '[]'::jsonb,
  difficulty smallint not null default 1 check (difficulty between 1 and 5),
  cognitive_level text not null default 'remember' check (cognitive_level in ('remember','understand','apply','analyze')),
  access_tier text not null default 'free' check (access_tier in ('free','subscription','one_time')),
  validation_status text not null default 'deterministic_validated' check (validation_status in ('deterministic_validated','educator_verified','review_required','retired')),
  source_status text not null default 'mela_supplemental',
  generation_version text not null default 'v11',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(program_key,question_number)
);

alter table public.mela_question_bank enable row level security;
revoke all on public.mela_question_bank from public, anon, authenticated;
grant select,insert,update,delete on public.mela_question_bank to service_role;

create schema if not exists private;

create table if not exists private.mela_question_answer_keys (
  question_id uuid primary key references public.mela_question_bank(id) on delete cascade,
  correct_choice text not null check (correct_choice in ('A','B','C','D')),
  correct_text text not null,
  explanation text not null,
  validation_method text not null default 'deterministic_mapping',
  validation_hash text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
revoke all on private.mela_question_answer_keys from public, anon, authenticated;
grant select,insert,update,delete on private.mela_question_answer_keys to service_role;

create table if not exists public.mela_question_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  program_key text not null references public.mela_learning_programs(program_key) on update cascade on delete restrict,
  question_ids uuid[] not null,
  requested_count smallint not null check (requested_count between 5 and 30),
  difficulty smallint check (difficulty between 1 and 5),
  seed text,
  status text not null default 'started' check (status in ('started','submitted','expired')),
  selected_answers jsonb not null default '[]'::jsonb,
  answered_count smallint not null default 0,
  correct_count smallint not null default 0,
  score_percent numeric(5,2),
  started_at timestamptz not null default now(),
  submitted_at timestamptz,
  expires_at timestamptz not null default (now()+interval '2 hours')
);

alter table public.mela_question_sessions enable row level security;
revoke all on public.mela_question_sessions from public, anon;
grant select on public.mela_question_sessions to authenticated;
grant select,insert,update,delete on public.mela_question_sessions to service_role;

drop policy if exists mela_question_sessions_owner_read on public.mela_question_sessions;
create policy mela_question_sessions_owner_read on public.mela_question_sessions
for select to authenticated
using ((select auth.uid())=user_id);

create table if not exists public.mela_question_review_batches (
  program_key text primary key references public.mela_learning_programs(program_key) on update cascade on delete cascade,
  grade_level smallint not null,
  subject_title text not null,
  target_question_count integer not null default 600,
  generated_question_count integer not null default 0,
  deterministic_validated_count integer not null default 0,
  educator_verified_count integer not null default 0,
  review_status text not null default 'generated_pending_educator_review' check (review_status in ('generated_pending_educator_review','in_review','approved','changes_required')),
  assigned_to uuid references public.profiles(id) on delete set null,
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.mela_question_review_batches enable row level security;
revoke all on public.mela_question_review_batches from public, anon, authenticated;
grant select,insert,update,delete on public.mela_question_review_batches to service_role;

create index if not exists mela_question_bank_program_number_idx on public.mela_question_bank(program_key,question_number) where active;
create index if not exists mela_question_bank_program_tier_diff_number_idx on public.mela_question_bank(program_key,access_tier,difficulty,question_number) where active;
create index if not exists mela_question_bank_chapter_idx on public.mela_question_bank(chapter_id) where active;
create index if not exists mela_question_bank_topic_idx on public.mela_question_bank(topic_id) where active;
create index if not exists mela_question_sessions_user_started_idx on public.mela_question_sessions(user_id,started_at desc);
create index if not exists mela_question_sessions_program_started_idx on public.mela_question_sessions(program_key,started_at desc);
create index if not exists mela_question_sessions_status_expiry_idx on public.mela_question_sessions(status,expires_at);
create index if not exists mela_question_review_batches_assigned_idx on public.mela_question_review_batches(assigned_to) where assigned_to is not null;
create index if not exists mela_question_review_batches_reviewed_idx on public.mela_question_review_batches(reviewed_by) where reviewed_by is not null;

create or replace function private.mela_user_has_question_access(p_uid uuid,p_tier text)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select case
    when p_tier='free' then true
    when p_uid is null then false
    when p_tier='subscription' then exists(
      select 1 from public.mela_user_learning_entitlements e
      where e.user_id=p_uid and e.status='active'
        and e.starts_at<=now() and (e.ends_at is null or e.ends_at>now())
        and e.product_key in ('school_plus_monthly','school_plus_annual','family_plus_monthly','institution_learning_license')
    )
    when p_tier='one_time' then exists(
      select 1 from public.mela_user_learning_entitlements e
      where e.user_id=p_uid and e.status='active'
        and e.starts_at<=now() and (e.ends_at is null or e.ends_at>now())
        and e.product_key in ('grade12_exam_master','institution_learning_license')
    )
    else false end;
$$;
revoke all on function private.mela_user_has_question_access(uuid,text) from public,anon,authenticated;
grant execute on function private.mela_user_has_question_access(uuid,text) to service_role;

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
  select count(*) into v_recent from public.mela_question_sessions where user_id=v_uid and started_at>now()-interval '1 hour';
  if v_recent>=120 then raise exception 'question-session rate limit reached; try again later'; end if;

  select 1 + mod(abs(hashtextextended(v_seed,0)),greatest(count(*),1))::integer into v_start
  from public.mela_question_bank q
  where q.program_key=p_program_key and q.active
    and (p_difficulty is null or q.difficulty=p_difficulty)
    and private.mela_user_has_question_access(v_uid,q.access_tier);

  with eligible as (
    select q.id,q.question_number,q.prompt,q.choices,q.difficulty,q.question_type,q.access_tier,q.validation_status,q.chapter_id,q.topic_id
    from public.mela_question_bank q
    where q.program_key=p_program_key and q.active
      and (p_difficulty is null or q.difficulty=p_difficulty)
      and private.mela_user_has_question_access(v_uid,q.access_tier)
  ), picked as (
    (select * from eligible where question_number>=v_start order by question_number limit v_count)
    union all
    (select * from eligible where question_number<v_start order by question_number limit v_count)
  ), final_pick as (
    select * from picked limit v_count
  )
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
revoke all on function private.start_mela_question_session(text,integer,smallint,text) from public,anon;
grant execute on function private.start_mela_question_session(text,integer,smallint,text) to authenticated,service_role;

create or replace function public.start_mela_question_session(p_program_key text,p_count integer default 20,p_difficulty smallint default null,p_seed text default null)
returns jsonb
language sql
security invoker
set search_path to ''
as $$ select private.start_mela_question_session(p_program_key,p_count,p_difficulty,p_seed); $$;
revoke all on function public.start_mela_question_session(text,integer,smallint,text) from public,anon;
grant execute on function public.start_mela_question_session(text,integer,smallint,text) to authenticated,service_role;

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

  return jsonb_build_object('session_id',p_session_id,'answered',v_answered,'total',v_total,'correct',v_correct,'score_percent',v_score,'feedback',v_feedback);
end;
$$;
revoke all on function private.submit_mela_question_session(uuid,jsonb) from public,anon;
grant execute on function private.submit_mela_question_session(uuid,jsonb) to authenticated,service_role;

create or replace function public.submit_mela_question_session(p_session_id uuid,p_answers jsonb)
returns jsonb
language sql
security invoker
set search_path to ''
as $$ select private.submit_mela_question_session(p_session_id,p_answers); $$;
revoke all on function public.submit_mela_question_session(uuid,jsonb) from public,anon;
grant execute on function public.submit_mela_question_session(uuid,jsonb) to authenticated,service_role;

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
        'educator_verified_count',(select count(*) from public.mela_question_bank q where q.program_key=p.program_key and q.active and q.validation_status='educator_verified')
      ) order by p.display_order,p.subject_title)
      from public.mela_learning_programs p
      where p.active and (v_role='admin' or (p.stage_key=v_stage and (p.grade_level is null or p.grade_level=v_grade)))
    ),'[]'::jsonb),
    'recent_sessions',coalesce((select jsonb_agg(to_jsonb(x) order by x.started_at desc) from (select id,program_key,status,requested_count,answered_count,correct_count,score_percent,started_at,submitted_at from public.mela_question_sessions where user_id=v_uid order by started_at desc limit 10) x),'[]'::jsonb)
  );
end;
$$;
revoke all on function private.get_my_question_bank_overview() from public,anon;
grant execute on function private.get_my_question_bank_overview() to authenticated,service_role;

create or replace function public.get_my_question_bank_overview()
returns jsonb
language sql
security invoker
set search_path to ''
as $$ select private.get_my_question_bank_overview(); $$;
revoke all on function public.get_my_question_bank_overview() from public,anon;
grant execute on function public.get_my_question_bank_overview() to authenticated,service_role;
;
