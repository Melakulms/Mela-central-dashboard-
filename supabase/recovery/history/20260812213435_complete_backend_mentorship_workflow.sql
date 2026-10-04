-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812213435
-- Mela V1 mentorship workflow hardening and automation.

-- Mentor visibility: only verified active mentors are publicly discoverable.
drop policy if exists "Active mentors public" on public.mentor_profiles;
drop policy if exists "Mentors readable authenticated" on public.mentor_profiles;
create policy "Verified active mentors public" on public.mentor_profiles for select to anon
using (verified=true and active=true);
create policy "Mentors readable authenticated" on public.mentor_profiles for select to authenticated
using ((verified=true and active=true) or user_id=(select auth.uid()) or private.is_admin_user());

drop policy if exists "Active mentor availability public anon" on public.mentor_availability;
drop policy if exists "Mentor availability readable authenticated" on public.mentor_availability;
create policy "Verified mentor availability public" on public.mentor_availability for select to anon
using (active=true and exists(select 1 from public.mentor_profiles mp where mp.user_id=mentor_id and mp.verified=true and mp.active=true));
create policy "Mentor availability readable authenticated" on public.mentor_availability for select to authenticated
using (
  mentor_id=(select auth.uid()) or private.is_admin_user()
  or (active=true and exists(select 1 from public.mentor_profiles mp where mp.user_id=mentor_id and mp.verified=true and mp.active=true))
);

-- Mentor verification changes role when safe, notifies the mentor, and creates an audit record.
create or replace function private.process_mentor_verification()
returns trigger language plpgsql security definer set search_path='pg_catalog','public','private' as $$
declare v_actor uuid := (select auth.uid());
begin
  if new.verified is distinct from old.verified then
    if new.verified then
      update public.profiles set role='mentor'::public.user_role,updated_at=now()
      where id=new.user_id and role='student'::public.user_role;
      perform private.create_notification(new.user_id,'Mentor profile verified','Your Mela mentor profile is now verified and discoverable.','mentor_profiles',new.user_id);
      insert into public.admin_audit_logs(actor_id,action,entity_type,entity_id,details)
      values(v_actor,'mentor_verified','mentor_profile',new.user_id,jsonb_build_object('verified',true));
    else
      update public.profiles set role='student'::public.user_role,updated_at=now()
      where id=new.user_id and role='mentor'::public.user_role;
      perform private.create_notification(new.user_id,'Mentor verification changed','Your mentor verification is no longer active.','mentor_profiles',new.user_id);
      insert into public.admin_audit_logs(actor_id,action,entity_type,entity_id,details)
      values(v_actor,'mentor_unverified','mentor_profile',new.user_id,jsonb_build_object('verified',false));
    end if;
  end if;
  return new;
end;$$;
revoke all on function private.process_mentor_verification() from public,anon,authenticated;
drop trigger if exists trg_process_mentor_verification on public.mentor_profiles;
create trigger trg_process_mentor_verification after update of verified on public.mentor_profiles
for each row execute function private.process_mentor_verification();

-- Requests: validated mentee creation, controlled mentor response, mentee cancellation.
drop policy if exists "Mentees delete pending requests" on public.mentorship_requests;
drop policy if exists "Mentees create mentorship requests" on public.mentorship_requests;
drop policy if exists "Mentorship requests readable by participants" on public.mentorship_requests;
drop policy if exists "Mentors respond to requests" on public.mentorship_requests;

create policy "Mentorship requests readable by participants" on public.mentorship_requests for select to authenticated
using (mentor_id=(select auth.uid()) or mentee_id=(select auth.uid()) or private.is_admin_user());
create policy "Mentees create mentorship requests" on public.mentorship_requests for insert to authenticated
with check (
  mentee_id=(select auth.uid()) and mentor_id<>(select auth.uid())
  and status='pending' and responded_at is null
  and (preferred_at is null or preferred_at>now())
  and exists(select 1 from public.mentor_profiles mp where mp.user_id=mentor_id and mp.verified=true and mp.active=true)
);
create policy "Mentors respond to requests" on public.mentorship_requests for update to authenticated
using (mentor_id=(select auth.uid()) and status='pending')
with check (mentor_id=(select auth.uid()) and status in ('accepted','declined'));
create policy "Mentees cancel pending requests" on public.mentorship_requests for update to authenticated
using (mentee_id=(select auth.uid()) and status='pending')
with check (mentee_id=(select auth.uid()) and status='cancelled');
create policy "Admins update mentorship requests" on public.mentorship_requests for update to authenticated
using (private.is_admin_user()) with check (private.is_admin_user());

revoke insert,update,delete on public.mentorship_requests from authenticated;
grant insert (mentor_id,mentee_id,topic,message,preferred_at,status) on public.mentorship_requests to authenticated;
grant update (status,preferred_at) on public.mentorship_requests to authenticated;

create or replace function private.enforce_mentorship_request_transition()
returns trigger language plpgsql set search_path='pg_catalog','public','private' as $$
declare v_uid uuid := (select auth.uid()); v_admin boolean := private.is_admin_user();
begin
  if new.mentor_id is distinct from old.mentor_id or new.mentee_id is distinct from old.mentee_id
     or new.topic is distinct from old.topic or new.message is distinct from old.message
     or new.created_at is distinct from old.created_at then
    raise exception 'mentorship request identity/content fields are immutable after submission';
  end if;
  if v_admin then
    if new.status is distinct from old.status and new.status in ('accepted','declined','cancelled') then new.responded_at=now(); end if;
    return new;
  end if;
  if v_uid=old.mentee_id then
    if old.status<>'pending' or new.status<>'cancelled' then raise exception 'mentee may only cancel a pending request'; end if;
    if new.preferred_at is distinct from old.preferred_at then raise exception 'mentee cannot change schedule during cancellation'; end if;
    new.responded_at=now();
    return new;
  end if;
  if v_uid=old.mentor_id then
    if old.status<>'pending' or new.status not in ('accepted','declined') then raise exception 'mentor may only accept or decline a pending request'; end if;
    if new.status='accepted' and (new.preferred_at is null or new.preferred_at<=now()) then raise exception 'accepted mentorship requires a future scheduled time'; end if;
    new.responded_at=now();
    return new;
  end if;
  raise exception 'not authorized to update mentorship request';
end;$$;
drop trigger if exists trg_enforce_mentorship_request_transition on public.mentorship_requests;
create trigger trg_enforce_mentorship_request_transition before update on public.mentorship_requests
for each row execute function private.enforce_mentorship_request_transition();

create unique index if not exists mentorship_sessions_request_unique_idx on public.mentorship_sessions(request_id) where request_id is not null;

create or replace function private.process_mentorship_request_status()
returns trigger language plpgsql security definer set search_path='pg_catalog','public','private' as $$
declare v_session_id uuid;
begin
  if new.status is not distinct from old.status then return new; end if;
  if new.status='accepted' then
    insert into public.mentorship_sessions(mentor_id,mentee_id,scheduled_at,duration_min,call_room_id,request_id,status)
    values(new.mentor_id,new.mentee_id,new.preferred_at,30,'mela-mentor-'||replace(gen_random_uuid()::text,'-',''),new.id,'scheduled')
    on conflict (request_id) where request_id is not null do update set scheduled_at=excluded.scheduled_at
    returning id into v_session_id;
    perform private.create_notification(new.mentee_id,'Mentorship request accepted','Your mentor accepted the request. A session has been scheduled.','mentorship_sessions',v_session_id);
    perform private.create_notification(new.mentor_id,'Mentorship session scheduled','Your accepted mentorship request is now scheduled.','mentorship_sessions',v_session_id);
  elsif new.status='declined' then
    perform private.create_notification(new.mentee_id,'Mentorship request declined','The mentor declined this request. You can request another verified mentor.','mentorship_requests',new.id);
  elsif new.status='cancelled' then
    perform private.create_notification(new.mentor_id,'Mentorship request cancelled','The mentee cancelled the pending request.','mentorship_requests',new.id);
  end if;
  return new;
end;$$;
revoke all on function private.process_mentorship_request_status() from public,anon,authenticated;
drop trigger if exists trg_process_mentorship_request_status on public.mentorship_requests;
create trigger trg_process_mentorship_request_status after update of status on public.mentorship_requests
for each row execute function private.process_mentorship_request_status();

-- Sessions are system-created from accepted requests; participants can only make allowed updates.
drop policy if exists "mentorship: participants manage" on public.mentorship_sessions;
create policy "Mentorship sessions readable by participants" on public.mentorship_sessions for select to authenticated
using (mentor_id=(select auth.uid()) or mentee_id=(select auth.uid()) or private.is_admin_user());
create policy "Mentorship sessions update by participants" on public.mentorship_sessions for update to authenticated
using (mentor_id=(select auth.uid()) or mentee_id=(select auth.uid()) or private.is_admin_user())
with check (mentor_id=(select auth.uid()) or mentee_id=(select auth.uid()) or private.is_admin_user());
create policy "Admins delete mentorship sessions" on public.mentorship_sessions for delete to authenticated
using (private.is_admin_user());

revoke insert,update,delete on public.mentorship_sessions from authenticated;
grant update (scheduled_at,duration_min,status,notes) on public.mentorship_sessions to authenticated;

create or replace function private.enforce_mentorship_session_update()
returns trigger language plpgsql set search_path='pg_catalog','public','private' as $$
declare v_uid uuid := (select auth.uid()); v_admin boolean := private.is_admin_user();
begin
  if new.id is distinct from old.id or new.mentor_id is distinct from old.mentor_id or new.mentee_id is distinct from old.mentee_id
     or new.request_id is distinct from old.request_id or new.call_room_id is distinct from old.call_room_id
     or new.recording_url is distinct from old.recording_url or new.guardian_notified is distinct from old.guardian_notified
     or new.created_at is distinct from old.created_at then
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
    ) then raise exception 'invalid mentorship session status transition'; end if;
    return new;
  end if;
  raise exception 'not authorized';
end;$$;
drop trigger if exists trg_enforce_mentorship_session_update on public.mentorship_sessions;
create trigger trg_enforce_mentorship_session_update before update on public.mentorship_sessions
for each row execute function private.enforce_mentorship_session_update();

create or replace function private.notify_mentorship_session_change()
returns trigger language plpgsql security definer set search_path='pg_catalog','public','private' as $$
begin
  if new.status is distinct from old.status then
    if new.status='completed' then
      perform private.create_notification(new.mentee_id,'Mentorship session completed','Your mentorship session was marked completed.','mentorship_sessions',new.id);
    elsif new.status='cancelled' then
      perform private.create_notification(case when (select auth.uid())=new.mentor_id then new.mentee_id else new.mentor_id end,'Mentorship session cancelled','A mentorship session was cancelled.','mentorship_sessions',new.id);
    end if;
  elsif new.scheduled_at is distinct from old.scheduled_at then
    perform private.create_notification(new.mentee_id,'Mentorship session rescheduled','Your mentor changed the scheduled session time.','mentorship_sessions',new.id);
  end if;
  return new;
end;$$;
revoke all on function private.notify_mentorship_session_change() from public,anon,authenticated;
drop trigger if exists trg_notify_mentorship_session_change on public.mentorship_sessions;
create trigger trg_notify_mentorship_session_change after update on public.mentorship_sessions
for each row execute function private.notify_mentorship_session_change();

create index if not exists mentorship_requests_mentor_status_idx on public.mentorship_requests(mentor_id,status,created_at desc);
create index if not exists mentorship_requests_mentee_status_idx on public.mentorship_requests(mentee_id,status,created_at desc);
create index if not exists mentorship_sessions_mentor_schedule_idx on public.mentorship_sessions(mentor_id,scheduled_at);
create index if not exists mentorship_sessions_mentee_schedule_idx on public.mentorship_sessions(mentee_id,scheduled_at);

;
