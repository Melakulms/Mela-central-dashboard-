-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812233924
create or replace function private.record_arena_integrity_event_for_user(p_user_id uuid,p_match_id uuid,p_event_type text,p_round_id uuid default null,p_details jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_severity smallint; v_count integer; v_weight integer; v_score numeric; v_status text;
begin
  if p_user_id is null then raise exception 'user required'; end if;
  if p_event_type not in ('tab_hidden','tab_visible','window_blur','window_focus','fullscreen_exit','fullscreen_enter','disconnect','reconnect','network_change','duplicate_session','suspicious_timing') then raise exception 'invalid integrity event'; end if;
  if pg_column_size(coalesce(p_details,'{}'::jsonb))>8192 then raise exception 'integrity event details too large'; end if;
  if not exists(select 1 from public.arena_matches m join public.arena_participants p on p.match_id=m.id where m.id=p_match_id and m.status='live' and p.user_id=p_user_id and p.status='active') then raise exception 'active arena participation required'; end if;
  if p_round_id is not null and not exists(select 1 from public.arena_rounds where id=p_round_id and match_id=p_match_id) then raise exception 'round does not belong to arena'; end if;
  v_severity:=case p_event_type when 'duplicate_session' then 5 when 'suspicious_timing' then 4 when 'tab_hidden' then 2 when 'fullscreen_exit' then 2 when 'disconnect' then 2 when 'network_change' then 1 when 'window_blur' then 1 else 1 end;
  insert into public.arena_integrity_events(match_id,user_id,round_id,event_type,severity,details) values(p_match_id,p_user_id,p_round_id,p_event_type,v_severity,coalesce(p_details,'{}'::jsonb));
  select count(*),coalesce(sum(severity),0) into v_count,v_weight from public.arena_integrity_events where match_id=p_match_id and user_id=p_user_id and event_type in ('tab_hidden','window_blur','fullscreen_exit','disconnect','duplicate_session','suspicious_timing');
  v_score:=greatest(0,100-v_weight*5);
  v_status:=case when v_score<50 then 'flagged' when v_score<80 then 'review' else 'clear' end;
  insert into public.arena_integrity_summaries(match_id,user_id,event_count,weighted_events,integrity_score,status,updated_at) values(p_match_id,p_user_id,v_count,v_weight,v_score,v_status,now())
  on conflict(match_id,user_id) do update set event_count=excluded.event_count,weighted_events=excluded.weighted_events,integrity_score=excluded.integrity_score,status=case when arena_integrity_summaries.status='disqualified' then 'disqualified' else excluded.status end,updated_at=now();
  update public.arena_participants set integrity_score=v_score,integrity_status=case when integrity_status='disqualified' then 'disqualified' else v_status end where match_id=p_match_id and user_id=p_user_id;
  return jsonb_build_object('integrity_score',v_score,'status',v_status,'event_count',v_count);
end $$;

create or replace function private.record_arena_integrity_event(p_match_id uuid,p_event_type text,p_round_id uuid default null,p_details jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=(select auth.uid());
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  return private.record_arena_integrity_event_for_user(v_uid,p_match_id,p_event_type,p_round_id,p_details);
end $$;

create or replace function private.start_arena_tournament_system(p_tournament_id uuid)
returns integer language plpgsql security definer set search_path='' as $$
declare v_t public.arena_tournaments; v_n integer; v_round uuid; a record; b record; v_pair uuid; v_created integer:=0; arr uuid[]; i integer;
begin
  select * into v_t from public.arena_tournaments where id=p_tournament_id for update;
  if v_t.id is null or v_t.status<>'registration' then raise exception 'tournament not ready for start'; end if;
  select count(*) into v_n from public.arena_tournament_competitors where tournament_id=p_tournament_id and status='registered';
  if v_n<2 then raise exception 'at least two competitors required'; end if;
  with s as (select id,row_number() over(order by created_at,id) seed from public.arena_tournament_competitors where tournament_id=p_tournament_id and status='registered') update public.arena_tournament_competitors c set seed=s.seed,status='active' from s where c.id=s.id;
  update public.arena_tournaments set status='in_progress',starts_at=coalesce(starts_at,now()),updated_at=now() where id=p_tournament_id;
  insert into public.arena_tournament_rounds(tournament_id,round_no,title,status,starts_at) values(p_tournament_id,1,case when v_t.format='round_robin' then 'Round Robin' else 'Round 1' end,'active',now()) returning id into v_round;
  if v_t.format='round_robin' then
    for a in select id,seed from public.arena_tournament_competitors where tournament_id=p_tournament_id and status='active' order by seed loop
      for b in select id from public.arena_tournament_competitors where tournament_id=p_tournament_id and status='active' and seed>a.seed order by seed loop
        insert into public.arena_tournament_pairings(tournament_round_id,competitor_a_id,competitor_b_id,status) values(v_round,a.id,b.id,'pending') returning id into v_pair;
        perform private.create_tournament_pairing_match(v_pair); v_created:=v_created+1;
      end loop;
    end loop;
  else
    select array_agg(id order by seed) into arr from public.arena_tournament_competitors where tournament_id=p_tournament_id and status='active';
    i:=1;
    while i<=array_length(arr,1) loop
      if i=array_length(arr,1) then insert into public.arena_tournament_pairings(tournament_round_id,competitor_a_id,competitor_b_id,winner_competitor_id,status,completed_at) values(v_round,arr[i],null,arr[i],'bye',now());
      else insert into public.arena_tournament_pairings(tournament_round_id,competitor_a_id,competitor_b_id,status) values(v_round,arr[i],arr[i+1],'pending') returning id into v_pair; perform private.create_tournament_pairing_match(v_pair); v_created:=v_created+1; end if;
      i:=i+2;
    end loop;
  end if;
  return v_created;
end $$;

create or replace function private.start_arena_tournament(p_tournament_id uuid)
returns integer language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=(select auth.uid());
begin
  if not exists(select 1 from public.arena_tournaments t where t.id=p_tournament_id and t.status='registration' and (t.created_by=v_uid or private.is_admin_user())) then raise exception 'tournament creator access required'; end if;
  return private.start_arena_tournament_system(p_tournament_id);
end $$;

create or replace function private.finalize_arena_match(p_match_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare v_m public.arena_matches;
begin
  select * into v_m from public.arena_matches where id=p_match_id for update;
  if v_m.id is null or v_m.status='completed' then return; end if;
  if v_m.team_mode then
    with team_scores as (select p.team_id,sum(coalesce(p.score,0)) s,min(p.joined_at) j from public.arena_participants p where p.match_id=p_match_id and p.team_id is not null and p.status in ('active','finished','disqualified') group by p.team_id), ranked as (select team_id,row_number() over(order by s desc,j asc,team_id) placement from team_scores)
    update public.arena_participants p set placement=r.placement,status=case when p.status='disqualified' then 'disqualified' else 'finished' end,finished_at=coalesce(p.finished_at,now()) from ranked r where p.match_id=p_match_id and p.team_id=r.team_id;
  else
    with ranked as (select user_id,row_number() over(order by score desc,joined_at asc,user_id) rn from public.arena_participants where match_id=p_match_id and status in ('active','finished','disqualified'))
    update public.arena_participants p set placement=r.rn,status=case when p.status='disqualified' then 'disqualified' else 'finished' end,finished_at=coalesce(p.finished_at,now()) from ranked r where p.match_id=p_match_id and p.user_id=r.user_id;
  end if;
  update public.arena_rounds set state=case when state='open' then 'closed' else state end,closed_at=case when state='open' then now() else closed_at end where match_id=p_match_id;
  update public.arena_matches set status='completed',ended_at=now(),round_ends_at=null,updated_at=now() where id=p_match_id;
end $$;

create or replace function private.submit_arena_round(p_round_id uuid,p_response jsonb,p_attachment_url text)
returns public.arena_round_submissions language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=(select auth.uid()); v_r public.arena_rounds; v_m public.arena_matches; v_correct jsonb; v_score numeric; v public.arena_round_submissions;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select r.* into v_r from public.arena_rounds r where r.id=p_round_id;
  if v_r.id is null then raise exception 'arena round not found'; end if;
  select * into v_m from public.arena_matches where id=v_r.match_id;
  if v_m.status<>'live' or v_r.state<>'open' or not exists(select 1 from public.arena_participants p where p.match_id=v_m.id and p.user_id=v_uid and p.status='active') then raise exception 'active open arena round required'; end if;
  if v_r.starts_at is not null and now()<v_r.starts_at then raise exception 'round has not started'; end if;
  if v_r.ends_at is not null and now()>v_r.ends_at then raise exception 'round is closed'; end if;
  v_score:=null;
  if v_r.round_type='quiz' and v_r.assessment_question_id is not null then select correct_answer into v_correct from private.assessment_answer_keys where question_id=v_r.assessment_question_id; if v_correct is not null then v_score:=case when p_response=v_correct then v_r.max_points else 0 end; end if; end if;
  insert into public.arena_round_submissions(round_id,match_id,user_id,response,attachment_url,score) values(p_round_id,v_m.id,v_uid,coalesce(p_response,'null'::jsonb),p_attachment_url,v_score)
  on conflict(round_id,user_id) do update set response=excluded.response,attachment_url=excluded.attachment_url,score=excluded.score,submitted_at=now(),feedback=null,reviewed_by=null,reviewed_at=null returning * into v;
  update public.arena_participants p set score=coalesce((select sum(coalesce(s.score,0))::int from public.arena_round_submissions s where s.match_id=v_m.id and s.user_id=v_uid),0) where p.match_id=v_m.id and p.user_id=v_uid;
  return v;
end $$;

revoke execute on function private.record_arena_integrity_event_for_user(uuid,uuid,text,uuid,jsonb),private.start_arena_tournament_system(uuid) from public,anon,authenticated;
;
