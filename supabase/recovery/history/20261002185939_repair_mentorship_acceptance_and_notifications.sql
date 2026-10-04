-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20261002185939
create or replace function private.enforce_mentorship_request_transition()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'public', 'private'
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_admin boolean := private.is_admin_user();
begin
  if new.mentor_id is distinct from old.mentor_id
     or new.mentee_id is distinct from old.mentee_id
     or new.topic is distinct from old.topic
     or new.message is distinct from old.message
     or new.created_at is distinct from old.created_at then
    raise exception 'mentorship request identity/content fields are immutable after submission';
  end if;

  if v_admin then
    if new.status is distinct from old.status and new.status in ('accepted','declined','cancelled') then
      new.responded_at = now();
    end if;
    return new;
  end if;

  if v_uid = old.mentee_id then
    if old.status <> 'pending' or new.status <> 'cancelled' then
      raise exception 'mentee may only cancel a pending request';
    end if;
    if new.preferred_at is distinct from old.preferred_at then
      raise exception 'mentee cannot change schedule during cancellation';
    end if;
    new.responded_at = now();
    return new;
  end if;

  if v_uid = old.mentor_id then
    if old.status <> 'pending' or new.status not in ('accepted','declined') then
      raise exception 'mentor may only accept or decline a pending request';
    end if;
    if new.status = 'accepted' and new.preferred_at is not null and new.preferred_at <= now() then
      raise exception 'preferred mentorship time must be in the future';
    end if;
    new.responded_at = now();
    return new;
  end if;

  raise exception 'not authorized to update mentorship request';
end;
$function$;

create or replace function private.process_mentorship_request_status()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $function$
declare
  v_session_id uuid;
begin
  if new.status is not distinct from old.status then
    return new;
  end if;

  if new.status = 'accepted' then
    if new.preferred_at is not null then
      insert into public.mentorship_sessions(
        mentor_id, mentee_id, scheduled_at, duration_min, call_room_id, request_id, status
      )
      values(
        new.mentor_id, new.mentee_id, new.preferred_at, 30,
        'mela-mentor-' || replace(gen_random_uuid()::text, '-', ''),
        new.id, 'scheduled'
      )
      on conflict (request_id) where request_id is not null do update
        set scheduled_at = excluded.scheduled_at,
            status = 'scheduled',
            cancelled_at = null,
            updated_at = now()
      returning id into v_session_id;

      perform private.create_notification(
        new.mentee_id,
        'Mentorship request accepted',
        'Your mentor accepted the request. A session has been scheduled.',
        'mentorship_sessions',
        v_session_id
      );
      perform private.create_notification(
        new.mentor_id,
        'Mentorship session scheduled',
        'Your accepted mentorship request is now scheduled.',
        'mentorship_sessions',
        v_session_id
      );
    else
      perform private.create_notification(
        new.mentee_id,
        'Mentorship request accepted',
        'Your mentor accepted the request. The mentor will schedule the session next.',
        'mentorship_requests',
        new.id
      );
      perform private.create_notification(
        new.mentor_id,
        'Mentorship request accepted',
        'Schedule the accepted mentorship request when you are ready.',
        'mentorship_requests',
        new.id
      );
    end if;
  elsif new.status = 'declined' then
    perform private.create_notification(
      new.mentee_id,
      'Mentorship request declined',
      'The mentor declined this request. You can request another verified mentor.',
      'mentorship_requests',
      new.id
    );
  elsif new.status = 'cancelled' then
    perform private.create_notification(
      new.mentor_id,
      'Mentorship request cancelled',
      'The mentee cancelled the pending request.',
      'mentorship_requests',
      new.id
    );
  end if;

  return new;
end;
$function$;

create or replace function private.cancel_mentorship_session(
  p_session_id uuid,
  p_reason text default null::text
)
returns public.mentorship_sessions
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_row public.mentorship_sessions%rowtype;
begin
  if v_uid is null then raise exception 'authentication required'; end if;

  select * into v_row
  from public.mentorship_sessions
  where id = p_session_id
  for update;

  if not found then raise exception 'session not found'; end if;
  if v_uid <> v_row.mentor_id and v_uid <> v_row.mentee_id and not private.is_admin_user() then
    raise exception 'not authorized';
  end if;
  if v_row.status <> 'scheduled' then
    raise exception 'only scheduled sessions can be cancelled';
  end if;

  update public.mentorship_sessions
  set status = 'cancelled',
      cancelled_at = now(),
      updated_at = now(),
      notes = coalesce(notes, '') ||
        case
          when nullif(trim(coalesce(p_reason, '')), '') is null then ''
          else E'\nCancellation: ' || trim(p_reason)
        end
  where id = p_session_id
  returning * into v_row;

  return v_row;
end;
$function$;

create or replace function private.complete_mentorship_session(
  p_session_id uuid,
  p_notes text default null::text
)
returns public.mentorship_sessions
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_row public.mentorship_sessions%rowtype;
begin
  if v_uid is null then raise exception 'authentication required'; end if;

  select * into v_row
  from public.mentorship_sessions
  where id = p_session_id
  for update;

  if not found then raise exception 'session not found'; end if;
  if v_row.mentor_id <> v_uid and not private.is_admin_user() then
    raise exception 'only mentor or admin can complete a session';
  end if;
  if v_row.status <> 'scheduled' then
    raise exception 'session is not scheduled';
  end if;

  update public.mentorship_sessions
  set status = 'completed',
      completed_at = now(),
      updated_at = now(),
      notes = coalesce(nullif(trim(coalesce(p_notes, '')), ''), notes)
  where id = p_session_id
  returning * into v_row;

  return v_row;
end;
$function$;
;
