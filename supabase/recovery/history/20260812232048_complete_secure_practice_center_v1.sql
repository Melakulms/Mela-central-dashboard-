-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812232048
create schema if not exists private;

-- Enrich the legacy practice catalog into the production Practice Center.
alter table public.practice_topics
  add column if not exists slug text,
  add column if not exists description text,
  add column if not exists career_path_id uuid references public.career_paths(id) on delete set null,
  add column if not exists module_id uuid references public.path_modules(id) on delete set null,
  add column if not exists source_lesson_id uuid references public.path_lessons(id) on delete set null,
  add column if not exists skill_tags text[] not null default '{}',
  add column if not exists is_published boolean not null default false,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

create unique index if not exists practice_topics_source_lesson_uq on public.practice_topics(source_lesson_id) where source_lesson_id is not null;
create unique index if not exists practice_topics_slug_uq on public.practice_topics(slug) where slug is not null;
create index if not exists practice_topics_path_idx on public.practice_topics(career_path_id, is_published);

alter table public.practice_questions
  add column if not exists question_type text not null default 'mcq',
  add column if not exists max_points numeric not null default 1,
  add column if not exists skill_tags text[] not null default '{}',
  add column if not exists source_lesson_id uuid references public.path_lessons(id) on delete set null,
  add column if not exists is_published boolean not null default false,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

do $$ begin
  if not exists (select 1 from pg_constraint where conname='practice_question_type_chk') then
    alter table public.practice_questions add constraint practice_question_type_chk
      check (question_type in ('mcq','true_false','short_answer','scenario','case_study','coding','file_upload','video_response'));
  end if;
  if not exists (select 1 from pg_constraint where conname='practice_question_difficulty_chk') then
    alter table public.practice_questions add constraint practice_question_difficulty_chk check (difficulty between 1 and 3);
  end if;
  if not exists (select 1 from pg_constraint where conname='practice_question_points_chk') then
    alter table public.practice_questions add constraint practice_question_points_chk check (max_points > 0 and max_points <= 100);
  end if;
end $$;

create index if not exists practice_questions_topic_idx on public.practice_questions(topic_id, is_published, difficulty);
create index if not exists practice_questions_source_lesson_idx on public.practice_questions(source_lesson_id);

-- Answer keys/rubrics are never exposed through the Data API.
create table if not exists private.practice_answer_keys(
  question_id uuid primary key references public.practice_questions(id) on delete cascade,
  correct_answer jsonb,
  rubric jsonb,
  explanation text,
  auto_gradable boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
revoke all on private.practice_answer_keys from public, anon, authenticated;

-- Move any legacy answers to the private schema before removing the exposed column.
do $$ begin
  if exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='practice_questions' and column_name='correct_answer'
  ) then
    insert into private.practice_answer_keys(question_id, correct_answer, auto_gradable)
    select id, jsonb_build_object('answer', correct_answer), true
    from public.practice_questions
    where correct_answer is not null
    on conflict (question_id) do nothing;
    alter table public.practice_questions drop column correct_answer;
  end if;
end $$;

create table if not exists public.practice_sessions(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  topic_id uuid not null references public.practice_topics(id) on delete restrict,
  mode text not null default 'untimed',
  difficulty smallint,
  status text not null default 'in_progress',
  question_count integer not null default 0,
  answered_count integer not null default 0,
  correct_count integer not null default 0,
  score_percent numeric,
  time_limit_seconds integer,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  total_time_seconds integer not null default 0,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint practice_session_mode_chk check (mode in ('learn','untimed','timed','mock','daily','weak_skill')),
  constraint practice_session_status_chk check (status in ('in_progress','completed','abandoned')),
  constraint practice_session_difficulty_chk check (difficulty is null or difficulty between 1 and 3),
  constraint practice_session_question_count_chk check (question_count between 0 and 30)
);
create index if not exists practice_sessions_user_idx on public.practice_sessions(user_id, started_at desc);
create index if not exists practice_sessions_topic_idx on public.practice_sessions(topic_id, started_at desc);

create table if not exists public.practice_session_questions(
  session_id uuid not null references public.practice_sessions(id) on delete cascade,
  question_id uuid not null references public.practice_questions(id) on delete restrict,
  question_order integer not null,
  max_points numeric not null default 1,
  primary key(session_id, question_id),
  unique(session_id, question_order)
);
create index if not exists practice_session_questions_question_idx on public.practice_session_questions(question_id);

alter table public.practice_attempts
  add column if not exists session_id uuid references public.practice_sessions(id) on delete cascade,
  add column if not exists response jsonb,
  add column if not exists score numeric,
  add column if not exists max_points numeric,
  add column if not exists feedback text,
  add column if not exists time_spent_seconds integer not null default 0,
  add column if not exists attachment_path text,
  add column if not exists reviewed_by uuid references public.profiles(id) on delete set null,
  add column if not exists reviewed_at timestamptz;
create unique index if not exists practice_attempts_session_question_uq on public.practice_attempts(session_id, question_id) where session_id is not null;
create index if not exists practice_attempts_user_time_idx on public.practice_attempts(user_id, attempted_at desc);
create index if not exists practice_attempts_session_idx on public.practice_attempts(session_id);

create table if not exists public.practice_mastery(
  user_id uuid not null references public.profiles(id) on delete cascade,
  topic_id uuid not null references public.practice_topics(id) on delete cascade,
  auto_questions_attempted integer not null default 0,
  auto_questions_correct integer not null default 0,
  accuracy_percent numeric not null default 0,
  mastery_score numeric not null default 0,
  mastery_level text not null default 'new',
  sessions_completed integer not null default 0,
  last_practiced_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key(user_id, topic_id),
  constraint practice_mastery_level_chk check (mastery_level in ('new','weak','developing','strong','mastered')),
  constraint practice_mastery_pct_chk check (accuracy_percent between 0 and 100 and mastery_score between 0 and 100)
);
create index if not exists practice_mastery_user_score_idx on public.practice_mastery(user_id, mastery_score, updated_at desc);

create table if not exists public.practice_user_stats(
  user_id uuid primary key references public.profiles(id) on delete cascade,
  total_sessions integer not null default 0,
  total_questions integer not null default 0,
  correct_answers integer not null default 0,
  total_time_seconds bigint not null default 0,
  current_streak_days integer not null default 0,
  longest_streak_days integer not null default 0,
  last_practice_date date,
  updated_at timestamptz not null default now()
);

-- Seed 32 topics directly from the already-published Skill Academy practice lessons.
insert into public.practice_topics(subject, topic, grade_level, slug, description, career_path_id, module_id, source_lesson_id, skill_tags, is_published)
select cp.title,
       pl.title,
       'career',
       'academy-' || replace(pl.id::text,'-',''),
       coalesce(pl.summary, pl.practical_activity, 'Mela Skill Academy practice'),
       cp.id,
       pm.id,
       pl.id,
       array[cp.title, pm.title, pl.title],
       true
from public.path_lessons pl
join public.path_modules pm on pm.id=pl.module_id
join public.career_paths cp on cp.id=pm.career_path_id
where pl.lesson_type='practice' and pl.is_published=true
on conflict (source_lesson_id) where source_lesson_id is not null do update set
  subject=excluded.subject, topic=excluded.topic, description=excluded.description,
  career_path_id=excluded.career_path_id, module_id=excluded.module_id,
  skill_tags=excluded.skill_tags, is_published=true, updated_at=now();

-- Three secure MCQs per topic, using the lesson's trusted key points.
with kp as (
  select pt.id topic_id, pl.id lesson_id, pl.title lesson_title,
         k.value #>> '{}' as key_point, k.ordinality ord
  from public.practice_topics pt
  join public.path_lessons pl on pl.id=pt.source_lesson_id
  cross join lateral jsonb_array_elements(pl.key_points) with ordinality k(value, ordinality)
), ins as (
  insert into public.practice_questions(topic_id, question, choices, difficulty, question_type, max_points, skill_tags, source_lesson_id, is_published)
  select topic_id,
         'For '||lesson_title||', which approach best reflects good Mela practice?',
         case ord
           when 1 then jsonb_build_array('Choose speed over accuracy and skip documentation.', key_point, 'Ignore privacy or safety when the task looks simple.', 'Use assumptions instead of checking evidence.')
           when 2 then jsonb_build_array('Ignore privacy or safety when the task looks simple.', 'Use assumptions instead of checking evidence.', key_point, 'Choose speed over accuracy and skip documentation.')
           else jsonb_build_array(key_point, 'Choose speed over accuracy and skip documentation.', 'Use assumptions instead of checking evidence.', 'Ignore privacy or safety when the task looks simple.')
         end,
         least(ord::smallint,3::smallint), 'mcq', 1,
         array[lesson_title], lesson_id, true
  from kp
  where not exists (
    select 1 from public.practice_questions q
    where q.source_lesson_id=kp.lesson_id and q.question_type='mcq' and q.question='For '||kp.lesson_title||', which approach best reflects good Mela practice?'
      and q.difficulty=least(kp.ord::smallint,3::smallint)
  )
  returning id, source_lesson_id, difficulty
)
insert into private.practice_answer_keys(question_id, correct_answer, rubric, explanation, auto_gradable)
select i.id,
       jsonb_build_object('answer', (select k.value #>> '{}' from public.path_lessons pl cross join lateral jsonb_array_elements(pl.key_points) with ordinality k(value,ordinality) where pl.id=i.source_lesson_id and k.ordinality=i.difficulty limit 1)),
       null,
       'Practice feedback: choose the option that protects quality, evidence, communication, safety, privacy and professional standards.',
       true
from ins i
on conflict (question_id) do update set correct_answer=excluded.correct_answer, explanation=excluded.explanation, auto_gradable=true, updated_at=now();

-- One scenario exercise and one reflection exercise per topic.
with ins as (
  insert into public.practice_questions(topic_id, question, choices, difficulty, question_type, max_points, skill_tags, source_lesson_id, is_published)
  select pt.id, pl.practical_activity, '[]'::jsonb, 2, 'scenario', 5, array[pl.title], pl.id, true
  from public.practice_topics pt join public.path_lessons pl on pl.id=pt.source_lesson_id
  where nullif(pl.practical_activity,'') is not null
    and not exists (select 1 from public.practice_questions q where q.source_lesson_id=pl.id and q.question_type='scenario')
  returning id
)
insert into private.practice_answer_keys(question_id, rubric, explanation, auto_gradable)
select id,
       jsonb_build_object('criteria',jsonb_build_array('Applies the lesson concept','Uses evidence or clear reasoning','Produces a clear workplace-ready output','Recognizes safety, privacy, quality or escalation needs where relevant')),
       'This is a practice exercise. Use the rubric to self-review; it does not create a verified skill by itself.', false
from ins on conflict (question_id) do nothing;

with ins as (
  insert into public.practice_questions(topic_id, question, choices, difficulty, question_type, max_points, skill_tags, source_lesson_id, is_published)
  select pt.id, pl.reflection_question, '[]'::jsonb, 3, 'short_answer', 3, array[pl.title], pl.id, true
  from public.practice_topics pt join public.path_lessons pl on pl.id=pt.source_lesson_id
  where nullif(pl.reflection_question,'') is not null
    and not exists (select 1 from public.practice_questions q where q.source_lesson_id=pl.id and q.question_type='short_answer')
  returning id
)
insert into private.practice_answer_keys(question_id, rubric, explanation, auto_gradable)
select id,
       jsonb_build_object('criteria',jsonb_build_array('Identifies a plausible beginner mistake','Explains why it matters','Provides a concrete prevention step')),
       'This reflection is for learning and self-review; it is not a proctored assessment.', false
from ins on conflict (question_id) do nothing;

-- RLS and explicit Data API grants.
alter table public.practice_topics enable row level security;
alter table public.practice_questions enable row level security;
alter table public.practice_sessions enable row level security;
alter table public.practice_session_questions enable row level security;
alter table public.practice_attempts enable row level security;
alter table public.practice_mastery enable row level security;
alter table public.practice_user_stats enable row level security;

-- Remove legacy broad policies and direct write access.
drop policy if exists "practice_topics: public read" on public.practice_topics;
drop policy if exists "practice_questions: public read" on public.practice_questions;
drop policy if exists "Practice attempts self delete" on public.practice_attempts;
drop policy if exists "Practice attempts self insert" on public.practice_attempts;
drop policy if exists "Practice attempts self select" on public.practice_attempts;
drop policy if exists "Practice attempts self update" on public.practice_attempts;

drop policy if exists practice_topics_public_read on public.practice_topics;
create policy practice_topics_public_read on public.practice_topics for select to anon, authenticated using (is_published=true);
drop policy if exists practice_questions_public_read on public.practice_questions;
create policy practice_questions_public_read on public.practice_questions for select to anon, authenticated using (is_published=true and exists(select 1 from public.practice_topics t where t.id=topic_id and t.is_published=true));
drop policy if exists practice_sessions_self_read on public.practice_sessions;
create policy practice_sessions_self_read on public.practice_sessions for select to authenticated using ((select auth.uid())=user_id);
drop policy if exists practice_session_questions_self_read on public.practice_session_questions;
create policy practice_session_questions_self_read on public.practice_session_questions for select to authenticated using (exists(select 1 from public.practice_sessions s where s.id=session_id and s.user_id=(select auth.uid())));
drop policy if exists practice_attempts_self_read on public.practice_attempts;
create policy practice_attempts_self_read on public.practice_attempts for select to authenticated using ((select auth.uid())=user_id);
drop policy if exists practice_mastery_self_read on public.practice_mastery;
create policy practice_mastery_self_read on public.practice_mastery for select to authenticated using ((select auth.uid())=user_id);
drop policy if exists practice_user_stats_self_read on public.practice_user_stats;
create policy practice_user_stats_self_read on public.practice_user_stats for select to authenticated using ((select auth.uid())=user_id);

revoke all on public.practice_topics, public.practice_questions, public.practice_sessions, public.practice_session_questions, public.practice_attempts, public.practice_mastery, public.practice_user_stats from anon, authenticated;
grant select on public.practice_topics, public.practice_questions to anon;
grant select on public.practice_topics, public.practice_questions to authenticated;
grant select on public.practice_sessions, public.practice_session_questions, public.practice_attempts, public.practice_mastery, public.practice_user_stats to authenticated;

-- Private state-machine implementation.
create or replace function private.start_practice_session(p_topic_id uuid, p_mode text default 'untimed', p_question_count integer default 10, p_difficulty smallint default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_uid uuid := auth.uid(); v_session uuid; v_count int;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  if p_mode not in ('learn','untimed','timed','mock','daily','weak_skill') then raise exception 'Invalid practice mode'; end if;
  if p_question_count < 1 or p_question_count > 30 then raise exception 'question_count must be between 1 and 30'; end if;
  if p_difficulty is not null and (p_difficulty < 1 or p_difficulty > 3) then raise exception 'Invalid difficulty'; end if;
  if not exists(select 1 from public.practice_topics t where t.id=p_topic_id and t.is_published=true) then raise exception 'Practice topic not found'; end if;

  insert into public.practice_sessions(user_id,topic_id,mode,difficulty,time_limit_seconds)
  values(v_uid,p_topic_id,p_mode,p_difficulty,case when p_mode in ('timed','mock','daily') then greatest(300,p_question_count*90) else null end)
  returning id into v_session;

  insert into public.practice_session_questions(session_id,question_id,question_order,max_points)
  select v_session,q.id,row_number() over(order by md5(q.id::text||v_session::text)),q.max_points
  from public.practice_questions q
  where q.topic_id=p_topic_id and q.is_published=true and (p_difficulty is null or q.difficulty=p_difficulty)
  order by md5(q.id::text||v_session::text)
  limit p_question_count;

  select count(*) into v_count from public.practice_session_questions where session_id=v_session;
  if v_count=0 then delete from public.practice_sessions where id=v_session; raise exception 'No published practice questions match this selection'; end if;
  update public.practice_sessions set question_count=v_count, updated_at=now() where id=v_session;
  return v_session;
end $$;

create or replace function private.submit_practice_response(p_session_id uuid, p_question_id uuid, p_response jsonb, p_time_spent_seconds integer default 0, p_attachment_path text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_type text; v_max numeric; v_key jsonb; v_expl text; v_auto bool; v_correct bool:=null; v_score numeric:=null;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  if not exists(select 1 from public.practice_sessions s where s.id=p_session_id and s.user_id=v_uid and s.status='in_progress') then raise exception 'Active practice session not found'; end if;
  select q.question_type,sq.max_points,k.correct_answer,k.explanation,k.auto_gradable
  into v_type,v_max,v_key,v_expl,v_auto
  from public.practice_session_questions sq
  join public.practice_questions q on q.id=sq.question_id
  left join private.practice_answer_keys k on k.question_id=q.id
  where sq.session_id=p_session_id and sq.question_id=p_question_id;
  if not found then raise exception 'Question is not part of this practice session'; end if;

  if v_auto then
    v_correct := lower(trim(coalesce(p_response->>'answer',''))) = lower(trim(coalesce(v_key->>'answer','')));
    v_score := case when v_correct then v_max else 0 end;
  end if;

  insert into public.practice_attempts(id,user_id,question_id,session_id,response,is_correct,score,max_points,feedback,time_spent_seconds,attachment_path,attempted_at)
  values(gen_random_uuid(),v_uid,p_question_id,p_session_id,p_response,v_correct,v_score,v_max,
         case when v_auto then case when v_correct then 'Correct.' else coalesce(v_expl,'Review the lesson and try again.') end else coalesce(v_expl,'Submitted for self-review.') end,
         greatest(0,least(coalesce(p_time_spent_seconds,0),7200)),p_attachment_path,now())
  on conflict (session_id,question_id) where session_id is not null do update set
    response=excluded.response,is_correct=excluded.is_correct,score=excluded.score,max_points=excluded.max_points,
    feedback=excluded.feedback,time_spent_seconds=excluded.time_spent_seconds,attachment_path=excluded.attachment_path,attempted_at=now();

  update public.practice_sessions s set
    answered_count=(select count(*) from public.practice_attempts a where a.session_id=s.id),
    correct_count=(select count(*) from public.practice_attempts a where a.session_id=s.id and a.is_correct=true),
    total_time_seconds=(select coalesce(sum(a.time_spent_seconds),0)::int from public.practice_attempts a where a.session_id=s.id),
    updated_at=now()
  where s.id=p_session_id;

  return jsonb_build_object('is_correct',v_correct,'score',v_score,'max_points',v_max,'feedback',case when v_auto then case when v_correct then 'Correct.' else v_expl end else v_expl end,'auto_graded',v_auto);
end $$;

create or replace function private.complete_practice_session(p_session_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_topic uuid; v_total int; v_answered int; v_auto int; v_correct int; v_score numeric; v_today date:=current_date; v_last date; v_streak int; v_longest int;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  select topic_id,question_count into v_topic,v_total from public.practice_sessions where id=p_session_id and user_id=v_uid and status='in_progress' for update;
  if not found then raise exception 'Active practice session not found'; end if;
  select count(*),count(*) filter(where a.is_correct is not null),count(*) filter(where a.is_correct=true)
    into v_answered,v_auto,v_correct from public.practice_attempts a where a.session_id=p_session_id;
  if v_answered < v_total then raise exception 'Complete all practice questions before finishing the session'; end if;
  v_score := case when v_auto=0 then null else round((100.0*v_correct/v_auto)::numeric,2) end;

  update public.practice_sessions set status='completed',answered_count=v_answered,correct_count=v_correct,score_percent=v_score,completed_at=now(),updated_at=now() where id=p_session_id;

  insert into public.practice_mastery(user_id,topic_id) values(v_uid,v_topic) on conflict do nothing;
  update public.practice_mastery m set
    auto_questions_attempted=x.total_auto,
    auto_questions_correct=x.total_correct,
    accuracy_percent=case when x.total_auto=0 then 0 else round((100.0*x.total_correct/x.total_auto)::numeric,2) end,
    mastery_score=case when x.total_auto=0 then m.mastery_score else round((100.0*x.total_correct/x.total_auto)::numeric,2) end,
    mastery_level=case when x.total_auto=0 then m.mastery_level when (100.0*x.total_correct/x.total_auto)>=90 then 'mastered' when (100.0*x.total_correct/x.total_auto)>=80 then 'strong' when (100.0*x.total_correct/x.total_auto)>=60 then 'developing' else 'weak' end,
    sessions_completed=(select count(*) from public.practice_sessions s where s.user_id=v_uid and s.topic_id=v_topic and s.status='completed'),
    last_practiced_at=now(),updated_at=now()
  from (
    select count(*) filter(where a.is_correct is not null)::int total_auto,count(*) filter(where a.is_correct=true)::int total_correct
    from public.practice_attempts a join public.practice_questions q on q.id=a.question_id
    where a.user_id=v_uid and q.topic_id=v_topic
  ) x where m.user_id=v_uid and m.topic_id=v_topic;

  insert into public.practice_user_stats(user_id) values(v_uid) on conflict do nothing;
  select last_practice_date,current_streak_days,longest_streak_days into v_last,v_streak,v_longest from public.practice_user_stats where user_id=v_uid for update;
  v_streak := case when v_last=v_today then greatest(v_streak,1) when v_last=v_today-1 then v_streak+1 else 1 end;
  v_longest := greatest(v_longest,v_streak);
  update public.practice_user_stats st set
    total_sessions=(select count(*) from public.practice_sessions s where s.user_id=v_uid and s.status='completed'),
    total_questions=(select count(*) from public.practice_attempts a where a.user_id=v_uid),
    correct_answers=(select count(*) from public.practice_attempts a where a.user_id=v_uid and a.is_correct=true),
    total_time_seconds=(select coalesce(sum(a.time_spent_seconds),0) from public.practice_attempts a where a.user_id=v_uid),
    current_streak_days=v_streak,longest_streak_days=v_longest,last_practice_date=v_today,updated_at=now()
  where st.user_id=v_uid;

  return jsonb_build_object('session_id',p_session_id,'score_percent',v_score,'answered',v_answered,'auto_graded',v_auto,'correct',v_correct,
    'mastery',(select to_jsonb(m) from public.practice_mastery m where m.user_id=v_uid and m.topic_id=v_topic));
end $$;

create or replace function private.get_my_practice_dashboard()
returns jsonb language sql stable security definer set search_path='' as $$
select jsonb_build_object(
 'stats',coalesce((select to_jsonb(s) from public.practice_user_stats s where s.user_id=auth.uid()),jsonb_build_object('total_sessions',0,'total_questions',0,'correct_answers',0,'total_time_seconds',0,'current_streak_days',0,'longest_streak_days',0)),
 'recent_sessions',coalesce((select jsonb_agg(x order by x.started_at desc) from (select s.id,s.topic_id,t.subject,t.topic,s.mode,s.score_percent,s.status,s.started_at,s.completed_at from public.practice_sessions s join public.practice_topics t on t.id=s.topic_id where s.user_id=auth.uid() order by s.started_at desc limit 10)x),'[]'::jsonb),
 'weak_topics',coalesce((select jsonb_agg(x order by x.mastery_score asc) from (select m.topic_id,t.subject,t.topic,m.mastery_score,m.mastery_level,m.accuracy_percent,m.last_practiced_at from public.practice_mastery m join public.practice_topics t on t.id=m.topic_id where m.user_id=auth.uid() and m.mastery_level in ('weak','developing','new') order by m.mastery_score asc limit 10)x),'[]'::jsonb),
 'strong_topics',coalesce((select jsonb_agg(x order by x.mastery_score desc) from (select m.topic_id,t.subject,t.topic,m.mastery_score,m.mastery_level,m.accuracy_percent from public.practice_mastery m join public.practice_topics t on t.id=m.topic_id where m.user_id=auth.uid() and m.mastery_level in ('strong','mastered') order by m.mastery_score desc limit 10)x),'[]'::jsonb)
);
$$;

create or replace function public.start_practice_session(p_topic_id uuid,p_mode text default 'untimed',p_question_count integer default 10,p_difficulty smallint default null)
returns uuid language sql security invoker set search_path='' as $$ select private.start_practice_session(p_topic_id,p_mode,p_question_count,p_difficulty); $$;
create or replace function public.submit_practice_response(p_session_id uuid,p_question_id uuid,p_response jsonb,p_time_spent_seconds integer default 0,p_attachment_path text default null)
returns jsonb language sql security invoker set search_path='' as $$ select private.submit_practice_response(p_session_id,p_question_id,p_response,p_time_spent_seconds,p_attachment_path); $$;
create or replace function public.complete_practice_session(p_session_id uuid)
returns jsonb language sql security invoker set search_path='' as $$ select private.complete_practice_session(p_session_id); $$;
create or replace function public.get_my_practice_dashboard()
returns jsonb language sql stable security invoker set search_path='' as $$ select private.get_my_practice_dashboard(); $$;

revoke all on function public.start_practice_session(uuid,text,integer,smallint) from public,anon;
revoke all on function public.submit_practice_response(uuid,uuid,jsonb,integer,text) from public,anon;
revoke all on function public.complete_practice_session(uuid) from public,anon;
revoke all on function public.get_my_practice_dashboard() from public,anon;
grant execute on function public.start_practice_session(uuid,text,integer,smallint) to authenticated;
grant execute on function public.submit_practice_response(uuid,uuid,jsonb,integer,text) to authenticated;
grant execute on function public.complete_practice_session(uuid) to authenticated;
grant execute on function public.get_my_practice_dashboard() to authenticated;
grant execute on function private.start_practice_session(uuid,text,integer,smallint) to authenticated;
grant execute on function private.submit_practice_response(uuid,uuid,jsonb,integer,text) to authenticated;
grant execute on function private.complete_practice_session(uuid) to authenticated;
grant execute on function private.get_my_practice_dashboard() to authenticated;

-- Private practice submissions bucket. Users only access their own top-level folder.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('practice-submissions','practice-submissions',false,52428800,array['application/pdf','application/vnd.openxmlformats-officedocument.wordprocessingml.document','text/plain','text/csv','image/jpeg','image/png','image/webp','video/mp4','video/webm'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists practice_submissions_owner_select on storage.objects;
create policy practice_submissions_owner_select on storage.objects for select to authenticated using (bucket_id='practice-submissions' and (storage.foldername(name))[1]=(select auth.uid())::text);
drop policy if exists practice_submissions_owner_insert on storage.objects;
create policy practice_submissions_owner_insert on storage.objects for insert to authenticated with check (bucket_id='practice-submissions' and (storage.foldername(name))[1]=(select auth.uid())::text);
drop policy if exists practice_submissions_owner_update on storage.objects;
create policy practice_submissions_owner_update on storage.objects for update to authenticated using (bucket_id='practice-submissions' and (storage.foldername(name))[1]=(select auth.uid())::text) with check (bucket_id='practice-submissions' and (storage.foldername(name))[1]=(select auth.uid())::text);
drop policy if exists practice_submissions_owner_delete on storage.objects;
create policy practice_submissions_owner_delete on storage.objects for delete to authenticated using (bucket_id='practice-submissions' and (storage.foldername(name))[1]=(select auth.uid())::text);

;
