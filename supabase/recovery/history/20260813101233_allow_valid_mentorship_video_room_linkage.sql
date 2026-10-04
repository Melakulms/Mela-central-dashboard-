-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260813101233
create or replace function private.enforce_mentorship_session_update()
returns trigger
language plpgsql
set search_path to 'pg_catalog','public','private'
as $$
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
    if new.status is distinct from old.status and not (old.status='scheduled' and new.status in ('completed','cancelled')) then
      raise exception 'invalid mentorship session status transition';
    end if;
    return new;
  end if;
  raise exception 'not authorized';
end;
$$;
;
