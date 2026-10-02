CREATE OR REPLACE FUNCTION private.start_arena(p_match_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_m public.arena_matches;
  v_first public.arena_rounds;
  v_now timestamptz := now();
begin
  if (select auth.uid()) is null then raise exception 'authentication required'; end if;
  select * into v_m from public.arena_matches where id=p_match_id for update;
  if v_m.id is null or (v_m.creator_id is distinct from (select auth.uid()) and not private.is_admin_user()) then
    raise exception 'arena creator access required';
  end if;
  if v_m.status not in ('open','ready') then raise exception 'arena cannot start'; end if;
  if (select count(*) from public.arena_participants where match_id=p_match_id and status='joined')<v_m.min_participants then
    raise exception 'not enough participants';
  end if;

  if exists(select 1 from public.arena_participants where match_id=p_match_id and status='joined' and not ready) then
    raise exception 'all participants must be ready';
  end if;

  if v_m.assessment_id is not null and v_m.arena_type in ('quiz_battle','speed_quiz')
     and not exists(select 1 from public.arena_rounds where match_id=p_match_id) then
    if (select count(*) from public.assessment_questions q where q.assessment_id=v_m.assessment_id and q.active) < 8 then
      raise exception 'quiz assessment needs at least 8 active questions';
    end if;

    insert into public.arena_rounds(
      match_id,round_order,round_type,title,prompt,assessment_question_id,max_points,time_limit_seconds,state,config
    )
    select
      p_match_id,
      row_number() over(order by q.question_order),
      'quiz',
      'Question '||row_number() over(order by q.question_order),
      q.prompt,
      q.id,
      q.points,
      case when v_m.arena_type='speed_quiz' then 45 else 90 end,
      'planned',
      jsonb_build_object('choices',q.choices)
    from public.assessment_questions q
    where q.assessment_id=v_m.assessment_id and q.active=true
    order by q.question_order
    limit 8;
  end if;

  if not exists(select 1 from public.arena_rounds where match_id=p_match_id) then
    raise exception 'arena needs at least one round';
  end if;

  update public.arena_rounds
  set state='planned',starts_at=null,ends_at=null,opened_at=null,closed_at=null
  where match_id=p_match_id;

  select * into v_first from public.arena_rounds
  where match_id=p_match_id order by round_order limit 1;

  update public.arena_rounds
  set state='open',
      starts_at=v_now,
      opened_at=v_now,
      ends_at=v_now+make_interval(secs=>coalesce(v_first.time_limit_seconds,300))
  where id=v_first.id;

  update public.arena_matches
  set status='live',
      started_at=v_now,
      current_round_order=v_first.round_order,
      round_started_at=v_now,
      round_ends_at=v_now+make_interval(secs=>coalesce(v_first.time_limit_seconds,300)),
      updated_at=v_now
  where id=p_match_id;

  update public.arena_participants
  set status='active'
  where match_id=p_match_id and status='joined';
end
$function$
