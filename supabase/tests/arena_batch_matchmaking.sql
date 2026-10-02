begin;
do $test$
declare
  players uuid[] := array[gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid()];
  assessment uuid;
  player uuid;
begin
  insert into auth.users(id,email,raw_app_meta_data,raw_user_meta_data,email_confirmed_at,created_at,updated_at)
  select u,u::text||'@example.invalid','{"provider":"email"}','{"full_name":"Arena batch rollback test","role":"student"}',now(),now(),now()
  from unnest(players) u;
  update auth.users set email_confirmed_at=now() where id=any(players);
  insert into public.skill_assessments(title,status,question_count) values('Rollback batch fixture','published',8) returning id into assessment;
  insert into public.arena_matchmaking_queue(user_id,arena_type,assessment_id)
  select u,'speed_quiz',assessment from unnest(players) u;
  perform private.process_arena_matchmaking();
  if (select count(*) from public.arena_matches where assessment_id=assessment)<>2 then raise exception 'four players did not produce exactly two matches'; end if;
  foreach player in array players loop
    if (select count(*) from public.arena_participants p join public.arena_matches m on m.id=p.match_id where m.assessment_id=assessment and p.user_id=player)<>1 then
      raise exception 'player was matched more than once in the same batch';
    end if;
  end loop;
end $test$;
rollback;
select 'PASS: four waiting players form exactly two matches with no duplicate participants; fixtures rolled back' as regression_result;
