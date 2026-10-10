-- Permit mentors to restore cancelled appointments; preserve completed history.
CREATE OR REPLACE FUNCTION private.enforce_mentorship_session_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_admin boolean := private.is_admin_user();
  v_valid_room_link boolean := false;
begin
  if new.video_call_room_id is distinct from old.video_call_room_id
     or new.call_room_id is distinct from old.call_room_id then
    v_valid_room_link := old.video_call_room_id is null
      and new.video_call_room_id is not null
      and exists(
        select 1 from public.video_call_rooms r
        where r.id=new.video_call_room_id
          and r.room_type='mentorship'
          and r.reference_id=old.id
          and (new.call_room_id is not distinct from r.room_key or new.call_room_id is not distinct from old.call_room_id)
      );
  end if;

  if new.id is distinct from old.id
     or new.mentor_id is distinct from old.mentor_id
     or new.mentee_id is distinct from old.mentee_id
     or new.request_id is distinct from old.request_id
     or new.recording_url is distinct from old.recording_url
     or new.guardian_notified is distinct from old.guardian_notified
     or new.created_at is distinct from old.created_at
     or ((new.video_call_room_id is distinct from old.video_call_room_id or new.call_room_id is distinct from old.call_room_id) and not v_valid_room_link) then
    raise exception 'protected mentorship session fields cannot be changed';
  end if;

  if v_admin then return new; end if;
  if v_uid=old.mentee_id then
    if new.scheduled_at is distinct from old.scheduled_at or new.duration_min is distinct from old.duration_min then
      raise exception 'mentee cannot reschedule directly';
    end if;
    if new.status is distinct from old.status and not (old.status='scheduled' and new.status='cancelled') then
      raise exception 'mentee may only cancel a scheduled session';
    end if;
    return new;
  end if;
  if v_uid=old.mentor_id then
    if new.scheduled_at is distinct from old.scheduled_at and new.scheduled_at<=now() then raise exception 'session must be scheduled in the future'; end if;
    if new.duration_min is not null and (new.duration_min<15 or new.duration_min>180) then raise exception 'session duration must be 15-180 minutes'; end if;
    if new.status is distinct from old.status and not (
      (old.status='scheduled' and new.status in ('completed','cancelled'))
      or (old.status='cancelled' and new.status='scheduled' and new.scheduled_at>now()
          and new.cancelled_at is null and old.completed_at is null and new.completed_at is null)
    ) then
      raise exception 'invalid mentorship session status transition';
    end if;
    return new;
  end if;
  raise exception 'not authorized';
end;
$function$;

CREATE OR REPLACE FUNCTION private.schedule_mentorship_session(p_request_id uuid, p_scheduled_at timestamp with time zone, p_duration_min integer DEFAULT 30, p_call_room_id text DEFAULT NULL::text)
 RETURNS mentorship_sessions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid := (select auth.uid()); v_req public.mentorship_requests%rowtype; v_row public.mentorship_sessions%rowtype;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if p_scheduled_at<=now() then raise exception 'session must be scheduled in the future'; end if;
  if p_duration_min<15 or p_duration_min>180 then raise exception 'duration must be 15 to 180 minutes'; end if;
  select * into v_req from public.mentorship_requests where id=p_request_id for update;
  if not found or v_req.status<>'accepted' then raise exception 'accepted mentorship request required'; end if;
  if v_req.mentor_id<>v_uid and not private.is_admin_user() then raise exception 'only the mentor or admin can schedule'; end if;
  if exists(select 1 from public.mentorship_sessions where request_id=v_req.id and (status='completed' or completed_at is not null)) then
    raise exception 'completed mentorship sessions cannot be rescheduled';
  end if;
  insert into public.mentorship_sessions(request_id,mentor_id,mentee_id,scheduled_at,duration_min,call_room_id,status)
  values(v_req.id,v_req.mentor_id,v_req.mentee_id,p_scheduled_at,p_duration_min,nullif(trim(coalesce(p_call_room_id,'')),''),'scheduled')
  on conflict (request_id) where request_id is not null do update set
    scheduled_at=excluded.scheduled_at,duration_min=excluded.duration_min,call_room_id=excluded.call_room_id,status='scheduled',cancelled_at=null,updated_at=now()
  returning * into v_row;
  insert into public.notifications(user_id,title,body,ref_table,ref_id)
  values(v_req.mentee_id,'Mentorship session scheduled','Your mentorship session is scheduled for '||to_char(v_row.scheduled_at at time zone 'UTC','YYYY-MM-DD HH24:MI:SS')||' UTC ('||v_row.duration_min::text||' minutes).','mentorship_sessions',v_row.id)
  on conflict do nothing;
  return v_row;
end;
$function$;

revoke all on function private.schedule_mentorship_session(uuid,timestamptz,integer,text) from public,anon;
grant execute on function private.schedule_mentorship_session(uuid,timestamptz,integer,text) to authenticated,service_role;
