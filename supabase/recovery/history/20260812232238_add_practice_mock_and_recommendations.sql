-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812232238
alter table public.practice_sessions alter column topic_id drop not null;
alter table public.practice_sessions add column if not exists career_path_id uuid references public.career_paths(id) on delete set null;
create index if not exists practice_sessions_path_idx on public.practice_sessions(career_path_id, started_at desc);

do $$ begin
  if not exists (select 1 from pg_constraint where conname='practice_session_scope_chk') then
    alter table public.practice_sessions add constraint practice_session_scope_chk check (topic_id is not null or career_path_id is not null);
  end if;
end $$;

create or replace function private.start_practice_mock(p_career_path_id uuid,p_question_count integer default 20,p_difficulty smallint default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_session uuid; v_count int;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  if p_question_count < 5 or p_question_count > 30 then raise exception 'question_count must be between 5 and 30'; end if;
  if p_difficulty is not null and (p_difficulty<1 or p_difficulty>3) then raise exception 'Invalid difficulty'; end if;
  if not exists(select 1 from public.career_paths c where c.id=p_career_path_id) then raise exception 'Career path not found'; end if;

  insert into public.practice_sessions(user_id,topic_id,career_path_id,mode,difficulty,time_limit_seconds)
  values(v_uid,null,p_career_path_id,'mock',p_difficulty,greatest(600,p_question_count*90)) returning id into v_session;

  insert into public.practice_session_questions(session_id,question_id,question_order,max_points)
  select v_session,q.id,row_number() over(order by md5(q.id::text||v_session::text)),q.max_points
  from public.practice_questions q
  join public.practice_topics t on t.id=q.topic_id
  where t.career_path_id=p_career_path_id and t.is_published=true and q.is_published=true
    and q.question_type in ('mcq','true_false')
    and (p_difficulty is null or q.difficulty=p_difficulty)
  order by md5(q.id::text||v_session::text)
  limit p_question_count;

  select count(*) into v_count from public.practice_session_questions where session_id=v_session;
  if v_count < least(5,p_question_count) then delete from public.practice_sessions where id=v_session; raise exception 'Not enough published questions for this mock test'; end if;
  update public.practice_sessions set question_count=v_count,updated_at=now() where id=v_session;
  return v_session;
end $$;

create or replace function private.complete_practice_session(p_session_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_total int; v_answered int; v_auto int; v_correct int; v_score numeric; v_today date:=current_date; v_last date; v_streak int; v_longest int; v_topic uuid;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  select question_count into v_total from public.practice_sessions where id=p_session_id and user_id=v_uid and status='in_progress' for update;
  if not found then raise exception 'Active practice session not found'; end if;
  select count(*),count(*) filter(where a.is_correct is not null),count(*) filter(where a.is_correct=true)
    into v_answered,v_auto,v_correct from public.practice_attempts a where a.session_id=p_session_id;
  if v_answered < v_total then raise exception 'Complete all practice questions before finishing the session'; end if;
  v_score := case when v_auto=0 then null else round((100.0*v_correct/v_auto)::numeric,2) end;
  update public.practice_sessions set status='completed',answered_count=v_answered,correct_count=v_correct,score_percent=v_score,completed_at=now(),updated_at=now() where id=p_session_id;

  for v_topic in
    select distinct q.topic_id from public.practice_session_questions sq join public.practice_questions q on q.id=sq.question_id where sq.session_id=p_session_id
  loop
    insert into public.practice_mastery(user_id,topic_id) values(v_uid,v_topic) on conflict do nothing;
    update public.practice_mastery m set
      auto_questions_attempted=x.total_auto,
      auto_questions_correct=x.total_correct,
      accuracy_percent=case when x.total_auto=0 then 0 else round((100.0*x.total_correct/x.total_auto)::numeric,2) end,
      mastery_score=case when x.total_auto=0 then m.mastery_score else round((100.0*x.total_correct/x.total_auto)::numeric,2) end,
      mastery_level=case when x.total_auto=0 then m.mastery_level when (100.0*x.total_correct/x.total_auto)>=90 then 'mastered' when (100.0*x.total_correct/x.total_auto)>=80 then 'strong' when (100.0*x.total_correct/x.total_auto)>=60 then 'developing' else 'weak' end,
      sessions_completed=(select count(distinct a.session_id) from public.practice_attempts a join public.practice_questions q2 on q2.id=a.question_id join public.practice_sessions s2 on s2.id=a.session_id where a.user_id=v_uid and q2.topic_id=v_topic and s2.status='completed'),
      last_practiced_at=now(),updated_at=now()
    from (
      select count(*) filter(where a.is_correct is not null)::int total_auto,count(*) filter(where a.is_correct=true)::int total_correct
      from public.practice_attempts a join public.practice_questions q on q.id=a.question_id
      where a.user_id=v_uid and q.topic_id=v_topic
    ) x where m.user_id=v_uid and m.topic_id=v_topic;
  end loop;

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
    'topic_mastery',coalesce((select jsonb_agg(to_jsonb(m)) from public.practice_mastery m where m.user_id=v_uid and m.topic_id in (select q.topic_id from public.practice_session_questions sq join public.practice_questions q on q.id=sq.question_id where sq.session_id=p_session_id)),'[]'::jsonb));
end $$;

create or replace function private.get_my_practice_recommendations(p_limit integer default 10)
returns jsonb language sql stable security definer set search_path='' as $$
with candidates as (
  select t.id topic_id,t.subject,t.topic,t.career_path_id,
         coalesce(m.mastery_score,0) mastery_score,
         coalesce(m.mastery_level,'new') mastery_level,
         m.last_practiced_at,
         case
           when m.user_id is null then 'Not practiced yet'
           when m.mastery_score < 60 then 'Weak topic: prioritize focused practice'
           when m.mastery_score < 80 then 'Developing topic: practice again to reach strong mastery'
           else 'Refresh this topic to maintain mastery'
         end reason,
         case when coalesce(m.mastery_score,0)<60 then 1 when coalesce(m.mastery_score,0)<80 then 2 else 3 end priority,
         case when coalesce(m.mastery_score,0)<60 then 1 when coalesce(m.mastery_score,0)<80 then 2 else 3 end recommended_difficulty
  from public.practice_topics t
  left join public.practice_mastery m on m.topic_id=t.id and m.user_id=auth.uid()
  where t.is_published=true
  order by priority asc,coalesce(m.mastery_score,0) asc,m.last_practiced_at nulls first,t.topic
  limit greatest(1,least(coalesce(p_limit,10),25))
)
select coalesce(jsonb_agg(jsonb_build_object('topic_id',topic_id,'subject',subject,'topic',topic,'career_path_id',career_path_id,'mastery_score',mastery_score,'mastery_level',mastery_level,'reason',reason,'priority',priority,'recommended_mode','weak_skill','recommended_difficulty',recommended_difficulty)),'[]'::jsonb) from candidates;
$$;

create or replace function private.get_my_practice_dashboard()
returns jsonb language sql stable security definer set search_path='' as $$
select jsonb_build_object(
 'stats',coalesce((select to_jsonb(s) from public.practice_user_stats s where s.user_id=auth.uid()),jsonb_build_object('total_sessions',0,'total_questions',0,'correct_answers',0,'total_time_seconds',0,'current_streak_days',0,'longest_streak_days',0)),
 'recent_sessions',coalesce((select jsonb_agg(x order by x.started_at desc) from (
   select s.id,s.topic_id,s.career_path_id,coalesce(t.subject,c.title) subject,coalesce(t.topic,case when s.mode='mock' then 'Career Path Mock Test' else 'Practice Session' end) topic,s.mode,s.score_percent,s.status,s.started_at,s.completed_at
   from public.practice_sessions s left join public.practice_topics t on t.id=s.topic_id left join public.career_paths c on c.id=s.career_path_id where s.user_id=auth.uid() order by s.started_at desc limit 10)x),'[]'::jsonb),
 'weak_topics',coalesce((select jsonb_agg(x order by x.mastery_score asc) from (select m.topic_id,t.subject,t.topic,m.mastery_score,m.mastery_level,m.accuracy_percent,m.last_practiced_at from public.practice_mastery m join public.practice_topics t on t.id=m.topic_id where m.user_id=auth.uid() and m.mastery_level in ('weak','developing','new') order by m.mastery_score asc limit 10)x),'[]'::jsonb),
 'strong_topics',coalesce((select jsonb_agg(x order by x.mastery_score desc) from (select m.topic_id,t.subject,t.topic,m.mastery_score,m.mastery_level,m.accuracy_percent from public.practice_mastery m join public.practice_topics t on t.id=m.topic_id where m.user_id=auth.uid() and m.mastery_level in ('strong','mastered') order by m.mastery_score desc limit 10)x),'[]'::jsonb),
 'recommendations',private.get_my_practice_recommendations(10)
);
$$;

create or replace function public.start_practice_mock(p_career_path_id uuid,p_question_count integer default 20,p_difficulty smallint default null)
returns uuid language sql security invoker set search_path='' as $$ select private.start_practice_mock(p_career_path_id,p_question_count,p_difficulty); $$;
create or replace function public.get_my_practice_recommendations(p_limit integer default 10)
returns jsonb language sql stable security invoker set search_path='' as $$ select private.get_my_practice_recommendations(p_limit); $$;

revoke all on function public.start_practice_mock(uuid,integer,smallint) from public,anon;
revoke all on function public.get_my_practice_recommendations(integer) from public,anon;
grant execute on function public.start_practice_mock(uuid,integer,smallint) to authenticated;
grant execute on function public.get_my_practice_recommendations(integer) to authenticated;
grant execute on function private.start_practice_mock(uuid,integer,smallint) to authenticated;
grant execute on function private.get_my_practice_recommendations(integer) to authenticated;

;
