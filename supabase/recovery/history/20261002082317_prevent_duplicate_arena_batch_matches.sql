-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20261002082317
CREATE OR REPLACE FUNCTION private.process_arena_matchmaking()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare q1 record; q2 record; v_match uuid; v_count integer:=0; v_round_type text; v_prompt text;
begin
  update public.arena_matchmaking_queue set status='expired' where status='waiting' and expires_at<=now();
  for q1 in select * from public.arena_matchmaking_queue q where q.status='waiting' and q.expires_at>now() order by q.created_at for update skip locked loop
    -- The cursor includes rows already paired as q2 earlier in this batch.
    if not exists(select 1 from public.arena_matchmaking_queue where id=q1.id and status='waiting') then continue; end if;
    select q.* into q2 from public.arena_matchmaking_queue q where q.status='waiting' and q.id<>q1.id and q.user_id<>q1.user_id and q.arena_type=q1.arena_type and q.assessment_id is not distinct from q1.assessment_id and q.expires_at>now() and abs(q.rating_snapshot-q1.rating_snapshot)<=least(q.rating_range,q1.rating_range) order by abs(q.rating_snapshot-q1.rating_snapshot),q.created_at limit 1 for update skip locked;
    if q2.id is null then continue; end if;
    insert into public.arena_matches(title,description,arena_type,creator_id,visibility,assessment_id,career_path_id,min_participants,max_participants,team_mode,status,scoring_mode,rated,integrity_required,rules)
    values('Mela Matchmaking '||replace(initcap(replace(q1.arena_type,'_',' ')),'  ',' '),'Matched by Mela based on Arena rating.',q1.arena_type,q1.user_id,'private',q1.assessment_id,coalesce(q1.career_path_id,q2.career_path_id),2,2,false,'open',case when q1.arena_type in ('quiz_battle','speed_quiz') then 'auto' else 'judge' end,true,q1.arena_type in ('quiz_battle','speed_quiz'),jsonb_build_object('matchmaking',true)) returning id into v_match;
    insert into public.arena_participants(match_id,user_id,status,ready) values(v_match,q1.user_id,'joined',false),(v_match,q2.user_id,'joined',false);
    if q1.arena_type not in ('quiz_battle','speed_quiz') then
      v_round_type:=case q1.arena_type when 'interview_practice' then 'interview' when 'case_sprint' then 'case' else 'task' end;
      v_prompt:=case q1.arena_type when 'interview_practice' then 'Respond to the interview prompt and demonstrate structured communication.' when 'case_sprint' then 'Analyze the case, state assumptions, and submit a concise recommendation.' else 'Complete the skill sprint task and submit your work.' end;
      insert into public.arena_rounds(match_id,round_order,round_type,title,prompt,max_points,time_limit_seconds,state) values(v_match,1,v_round_type,'Round 1',v_prompt,100,900,'planned');
    end if;
    update public.arena_matchmaking_queue set status='matched',matched_match_id=v_match where id in (q1.id,q2.id);
    insert into public.notifications(user_id,title,body,ref_table,ref_id) values(q1.user_id,'Arena match found','Your Arena opponent is ready.','arena_matches',v_match),(q2.user_id,'Arena match found','Your Arena opponent is ready.','arena_matches',v_match);
    v_count:=v_count+1;
  end loop;
  return v_count;
end $function$

;
