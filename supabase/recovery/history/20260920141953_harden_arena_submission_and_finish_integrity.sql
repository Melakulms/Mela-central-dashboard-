-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260920141953

create or replace function private.finish_arena(p_match_id uuid)
returns void
language plpgsql security definer set search_path to ''
as $$
declare v_m public.arena_matches; v_uid uuid := (select auth.uid());
begin
  select * into v_m from public.arena_matches where id=p_match_id for update;
  if v_m.id is null then raise exception 'arena not found'; end if;
  if v_uid is null then raise exception 'authentication required'; end if;
  if v_m.creator_id<>v_uid and not private.is_admin_user() then raise exception 'arena creator access required'; end if;
  if v_m.status='completed' then return; end if;
  if v_m.status<>'live' then raise exception 'only a live arena can be finished'; end if;
  if not private.is_admin_user() and v_m.round_ends_at is not null and v_m.round_ends_at>now() then
    raise exception 'live arena cannot be finished before the current round ends';
  end if;
  perform private.finalize_arena_match(p_match_id);
end $$;

create or replace function private.submit_arena_round(p_round_id uuid, p_response jsonb, p_attachment_url text)
returns public.arena_round_submissions
language plpgsql security definer set search_path to ''
as $$
declare v_uid uuid:=(select auth.uid()); v_r public.arena_rounds; v_m public.arena_matches;
        v_correct jsonb; v_score numeric; v public.arena_round_submissions;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select r.* into v_r from public.arena_rounds r where r.id=p_round_id;
  if v_r.id is null then raise exception 'arena round not found'; end if;
  select * into v_m from public.arena_matches where id=v_r.match_id;
  if v_m.status<>'live' or v_r.state<>'open' or not exists(
    select 1 from public.arena_participants p where p.match_id=v_m.id and p.user_id=v_uid and p.status='active'
  ) then raise exception 'active open arena round required'; end if;
  if v_r.starts_at is not null and now()<v_r.starts_at then raise exception 'round has not started'; end if;
  if v_r.ends_at is not null and now()>v_r.ends_at then raise exception 'round is closed'; end if;
  if exists(select 1 from public.arena_round_submissions where round_id=p_round_id and user_id=v_uid) then
    raise exception 'this round has already been submitted';
  end if;
  if jsonb_typeof(coalesce(p_response,'null'::jsonb)) not in ('object','array','string','number','boolean','null') then
    raise exception 'invalid response payload';
  end if;
  v_score:=null;
  if v_r.round_type='quiz' and v_r.assessment_question_id is not null then
    select correct_answer into v_correct from private.assessment_answer_keys where question_id=v_r.assessment_question_id;
    if v_correct is not null then
      v_score:=case when p_response=v_correct then v_r.max_points else 0 end;
    end if;
  end if;
  insert into public.arena_round_submissions(round_id,match_id,user_id,response,attachment_url,score)
  values(p_round_id,v_m.id,v_uid,coalesce(p_response,'null'::jsonb),nullif(trim(p_attachment_url),''),v_score)
  returning * into v;
  update public.arena_participants p
  set score=coalesce((select sum(coalesce(s.score,0))::int from public.arena_round_submissions s where s.match_id=v_m.id and s.user_id=v_uid),0)
  where p.match_id=v_m.id and p.user_id=v_uid;
  return v;
end $$;

;
