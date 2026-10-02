begin;
do $test$
declare
  player_one uuid := gen_random_uuid();
  player_two uuid := gen_random_uuid();
  outsider uuid := gen_random_uuid();
  assessment uuid;
  test_match uuid;
  round_id uuid;
  submission public.arena_round_submissions;
  blocked boolean;
begin
  insert into auth.users(id,email,raw_app_meta_data,raw_user_meta_data,email_confirmed_at,created_at,updated_at)
  select u,u::text||'@example.invalid','{"provider":"email"}','{"full_name":"Arena rollback test","role":"student"}',now(),now(),now()
  from unnest(array[player_one,player_two,outsider]) u;
  update auth.users set email_confirmed_at=now() where id in (player_one,player_two,outsider);
  update public.profiles set account_status='active' where id in (player_one,player_two,outsider);
  insert into public.skill_assessments(title,status,question_count) values('Rollback Arena fixture','published',8) returning id into assessment;
  insert into public.assessment_questions(assessment_id,question_order,prompt,choices,points)
  select assessment,n,'Choose A','[{"id":"A","text":"Correct choice"},{"id":"B","text":"Other choice"}]',10 from generate_series(1,8) n;
  insert into private.assessment_answer_keys(question_id,correct_answer)
  select id,'"A"'::jsonb from public.assessment_questions where assessment_id=assessment;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',player_one,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  perform public.join_arena_matchmaking('speed_quiz',assessment,null,200);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',player_two,'role','authenticated')::text,true);
  perform public.join_arena_matchmaking('speed_quiz',assessment,null,200);
  select matched_match_id into test_match from public.arena_matchmaking_queue where user_id=player_two and status='matched';
  if test_match is null then raise exception 'players were not matched'; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',player_one,'role','authenticated')::text,true);
  blocked:=false;
  begin perform public.start_arena(test_match); exception when others then blocked:=true; end;
  if not blocked then raise exception 'match started before players were ready'; end if;
  perform public.set_arena_ready(test_match,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',player_two,'role','authenticated')::text,true);
  perform public.set_arena_ready(test_match,true);
  blocked:=false;
  begin perform public.start_arena(test_match); exception when others then blocked:=true; end;
  if not blocked then raise exception 'non-creator started a match'; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',player_one,'role','authenticated')::text,true);
  perform public.start_arena(test_match);
  if (public.get_arena_live_state(test_match)->>'status')<>'live' then raise exception 'match did not start'; end if;
  if (select count(*) from public.arena_rounds where arena_rounds.match_id=test_match)<>8 then raise exception 'match does not have eight rounds'; end if;
  execute 'reset role';
  update public.arena_matches set round_ends_at=now()-interval '1 minute' where id=test_match;
  execute 'set local role authenticated';
  blocked:=false;
  begin perform public.finish_arena(test_match); exception when others then blocked:=true; end;
  if not blocked then raise exception 'creator skipped seven rounds by finishing after round one'; end if;
  execute 'reset role';
  update public.arena_matches set round_ends_at=now()+interval '1 minute' where id=test_match;
  execute 'set local role authenticated';
  select r.id into round_id from public.arena_rounds r where r.match_id=test_match and round_order=1;
  if (select config->'choices'->0->>'id' from public.arena_rounds where id=round_id)<>'A' then raise exception 'choices were not copied'; end if;
  submission:=public.submit_arena_round(round_id,'"A"'::jsonb,null);
  if submission.score<>10 then raise exception 'correct answer not scored'; end if;
  blocked:=false;
  begin perform public.submit_arena_round(round_id,'"B"'::jsonb,null); exception when others then blocked:=true; end;
  if not blocked then raise exception 'duplicate submission accepted'; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',player_two,'role','authenticated')::text,true);
  submission:=public.submit_arena_round(round_id,'"B"'::jsonb,null);
  if submission.score<>0 then raise exception 'incorrect answer not scored'; end if;
  if (select count(*) from public.get_arena_live_scoreboard(test_match))<>2 then raise exception 'scoreboard missing players'; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',outsider,'role','authenticated')::text,true);
  blocked:=false;
  begin perform public.submit_arena_round(round_id,'"A"'::jsonb,null); exception when others then blocked:=true; end;
  if not blocked then raise exception 'outsider submitted a match answer'; end if;
end $test$;
rollback;
select 'PASS: two-player matchmaking, readiness, eight rounds, choices, grading, duplicate and outsider rejection; all fixtures rolled back' as regression_result;
