-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812213637
-- Production mentorship workflow and mentor verification.

alter table public.mentor_profiles add column if not exists verification_notes text;
alter table public.mentor_profiles add column if not exists verified_at timestamptz;
alter table public.mentor_profiles add column if not exists verified_by uuid references public.profiles(id) on delete set null;

alter table public.mentor_availability drop constraint if exists mentor_availability_weekday_chk;
alter table public.mentor_availability add constraint mentor_availability_weekday_chk check (weekday between 0 and 6);
alter table public.mentor_availability drop constraint if exists mentor_availability_time_chk;
alter table public.mentor_availability add constraint mentor_availability_time_chk check (start_time < end_time);

alter table public.mentorship_sessions add column if not exists updated_at timestamptz not null default now();
alter table public.mentorship_sessions add column if not exists cancelled_at timestamptz;
alter table public.mentorship_sessions add column if not exists completed_at timestamptz;
alter table public.mentorship_sessions drop constraint if exists mentorship_session_status_chk;
alter table public.mentorship_sessions add constraint mentorship_session_status_chk check (status in ('scheduled','completed','cancelled','no_show'));
create unique index if not exists mentorship_sessions_request_unique on public.mentorship_sessions(request_id) where request_id is not null;
create unique index if not exists mentorship_one_pending_pair on public.mentorship_requests(mentor_id,mentee_id) where status='pending';
create index if not exists mentorship_sessions_mentor_time_idx on public.mentorship_sessions(mentor_id,scheduled_at);
create index if not exists mentorship_sessions_mentee_time_idx on public.mentorship_sessions(mentee_id,scheduled_at);

create or replace function private.protect_mentor_verification()
returns trigger
language plpgsql
set search_path=''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_admin boolean := false;
begin
  if v_uid is not null then
    v_admin := private.is_admin_user();
    if tg_op='INSERT' then
      new.verified := false;
      new.verified_at := null;
      new.verified_by := null;
      new.verification_notes := null;
    elsif not v_admin and (
      new.verified is distinct from old.verified or
      new.verified_at is distinct from old.verified_at or
      new.verified_by is distinct from old.verified_by or
      new.verification_notes is distinct from old.verification_notes
    ) then
      raise exception 'mentor verification is admin managed';
    elsif v_admin and new.verified is distinct from old.verified then
      new.verified_by := v_uid;
      new.verified_at := now();
    end if;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.review_mentor_profile(p_mentor_id uuid, p_verified boolean, p_notes text default null)
returns public.mentor_profiles
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_row public.mentor_profiles%rowtype;
begin
  if v_uid is null or not private.is_admin_user() then raise exception 'admin authorization required'; end if;
  update public.mentor_profiles
     set verified=p_verified,
         verification_notes=nullif(trim(coalesce(p_notes,'')),'')
   where user_id=p_mentor_id
   returning * into v_row;
  if not found then raise exception 'mentor profile not found'; end if;
  if p_verified then
    update public.profiles set role='mentor'::public.user_role where id=p_mentor_id and role='student'::public.user_role;
  end if;
  insert into public.admin_audit_logs(actor_id,action,entity_type,entity_id,details)
  values(v_uid,'review_mentor_profile','mentor_profile',p_mentor_id,jsonb_build_object('verified',p_verified,'notes',p_notes));
  return v_row;
end;
$$;
revoke all on function public.review_mentor_profile(uuid,boolean,text) from public, anon;
grant execute on function public.review_mentor_profile(uuid,boolean,text) to authenticated, service_role;

-- Mentor discovery: only verified active mentors are public.
drop policy if exists "Active mentors public" on public.mentor_profiles;
drop policy if exists "Verified active mentors public" on public.mentor_profiles;
drop policy if exists "Mentors readable authenticated" on public.mentor_profiles;
create policy "Verified active mentors public" on public.mentor_profiles
for select to anon using (active=true and verified=true);
create policy "Mentors readable authenticated" on public.mentor_profiles
for select to authenticated
using ((active=true and verified=true) or user_id=(select auth.uid()) or private.is_admin_user());

drop policy if exists "Active mentor availability public anon" on public.mentor_availability;
drop policy if exists "Verified mentor availability public" on public.mentor_availability;
drop policy if exists "Mentor availability readable authenticated" on public.mentor_availability;
create policy "Verified mentor availability public" on public.mentor_availability
for select to anon
using (active=true and exists(select 1 from public.mentor_profiles m where m.user_id=mentor_id and m.active=true and m.verified=true));
create policy "Mentor availability readable authenticated" on public.mentor_availability
for select to authenticated
using ((active=true and exists(select 1 from public.mentor_profiles m where m.user_id=mentor_id and m.active=true and m.verified=true)) or mentor_id=(select auth.uid()) or private.is_admin_user());

-- Requests: direct insert/read only; mutations happen through RPCs.
drop policy if exists "Mentees create mentorship requests" on public.mentorship_requests;
drop policy if exists "Students create mentorship requests" on public.mentorship_requests;
drop policy if exists "Mentees delete pending requests" on public.mentorship_requests;
drop policy if exists "Mentees cancel pending requests" on public.mentorship_requests;
drop policy if exists "Mentors respond to requests" on public.mentorship_requests;
drop policy if exists "Admins update mentorship requests" on public.mentorship_requests;
create policy "Students create mentorship requests" on public.mentorship_requests
for insert to authenticated
with check (
  mentee_id=(select auth.uid()) and status='pending'
  and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='student'::public.user_role)
  and exists(select 1 from public.mentor_profiles m where m.user_id=mentor_id and m.verified=true and m.active=true)
);
revoke update, delete on public.mentorship_requests from authenticated;
grant select, insert on public.mentorship_requests to authenticated;

-- Sessions are read directly; workflow mutations go through RPCs.
drop policy if exists "mentorship: participants manage" on public.mentorship_sessions;
drop policy if exists "Mentorship sessions update by participants" on public.mentorship_sessions;
drop policy if exists "Admins delete mentorship sessions" on public.mentorship_sessions;
drop policy if exists "Mentorship sessions readable by participants" on public.mentorship_sessions;
create policy "Mentorship sessions readable by participants" on public.mentorship_sessions
for select to authenticated
using (mentor_id=(select auth.uid()) or mentee_id=(select auth.uid()) or private.is_admin_user());
revoke insert, update, delete on public.mentorship_sessions from authenticated;
grant select on public.mentorship_sessions to authenticated;

create or replace function public.cancel_mentorship_request(p_request_id uuid)
returns public.mentorship_requests
language plpgsql security definer set search_path=''
as $$
declare v_uid uuid := (select auth.uid()); v_row public.mentorship_requests%rowtype;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select * into v_row from public.mentorship_requests where id=p_request_id for update;
  if not found then raise exception 'request not found'; end if;
  if v_row.mentee_id<>v_uid and not private.is_admin_user() then raise exception 'not authorized'; end if;
  if v_row.status<>'pending' then raise exception 'only pending requests can be cancelled'; end if;
  update public.mentorship_requests set status='cancelled',responded_at=now() where id=p_request_id returning * into v_row;
  insert into public.notifications(user_id,title,body,ref_table,ref_id)
  values(v_row.mentor_id,'Mentorship request cancelled','A mentorship request was cancelled.','mentorship_requests',v_row.id);
  return v_row;
end;
$$;

create or replace function public.respond_mentorship_request(p_request_id uuid, p_decision text)
returns public.mentorship_requests
language plpgsql security definer set search_path=''
as $$
declare v_uid uuid := (select auth.uid()); v_row public.mentorship_requests%rowtype;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if p_decision not in ('accepted','declined') then raise exception 'decision must be accepted or declined'; end if;
  select * into v_row from public.mentorship_requests where id=p_request_id for update;
  if not found then raise exception 'request not found'; end if;
  if v_row.mentor_id<>v_uid and not private.is_admin_user() then raise exception 'only the mentor or admin can respond'; end if;
  if v_row.status<>'pending' then raise exception 'request is no longer pending'; end if;
  update public.mentorship_requests set status=p_decision,responded_at=now() where id=p_request_id returning * into v_row;
  insert into public.notifications(user_id,title,body,ref_table,ref_id)
  values(v_row.mentee_id,'Mentorship request update','Your mentorship request was '||p_decision||'.','mentorship_requests',v_row.id);
  return v_row;
end;
$$;

create or replace function public.schedule_mentorship_session(p_request_id uuid, p_scheduled_at timestamptz, p_duration_min integer default 30, p_call_room_id text default null)
returns public.mentorship_sessions
language plpgsql security definer set search_path=''
as $$
declare v_uid uuid := (select auth.uid()); v_req public.mentorship_requests%rowtype; v_row public.mentorship_sessions%rowtype;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if p_scheduled_at<=now() then raise exception 'session must be scheduled in the future'; end if;
  if p_duration_min<15 or p_duration_min>180 then raise exception 'duration must be 15 to 180 minutes'; end if;
  select * into v_req from public.mentorship_requests where id=p_request_id for update;
  if not found or v_req.status<>'accepted' then raise exception 'accepted mentorship request required'; end if;
  if v_req.mentor_id<>v_uid and not private.is_admin_user() then raise exception 'only the mentor or admin can schedule'; end if;
  insert into public.mentorship_sessions(request_id,mentor_id,mentee_id,scheduled_at,duration_min,call_room_id,status)
  values(v_req.id,v_req.mentor_id,v_req.mentee_id,p_scheduled_at,p_duration_min,nullif(trim(coalesce(p_call_room_id,'')),''),'scheduled')
  on conflict (request_id) where request_id is not null do update set
    scheduled_at=excluded.scheduled_at,duration_min=excluded.duration_min,call_room_id=excluded.call_room_id,status='scheduled',cancelled_at=null,updated_at=now()
  returning * into v_row;
  insert into public.notifications(user_id,title,body,ref_table,ref_id)
  values(v_req.mentee_id,'Mentorship session scheduled','Your mentorship session has been scheduled.','mentorship_sessions',v_row.id);
  return v_row;
end;
$$;

create or replace function public.cancel_mentorship_session(p_session_id uuid, p_reason text default null)
returns public.mentorship_sessions
language plpgsql security definer set search_path=''
as $$
declare v_uid uuid := (select auth.uid()); v_row public.mentorship_sessions%rowtype; v_other uuid;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select * into v_row from public.mentorship_sessions where id=p_session_id for update;
  if not found then raise exception 'session not found'; end if;
  if v_uid<>v_row.mentor_id and v_uid<>v_row.mentee_id and not private.is_admin_user() then raise exception 'not authorized'; end if;
  if v_row.status<>'scheduled' then raise exception 'only scheduled sessions can be cancelled'; end if;
  update public.mentorship_sessions
     set status='cancelled',cancelled_at=now(),updated_at=now(),notes=coalesce(notes,'')||case when nullif(trim(coalesce(p_reason,'')),'') is null then '' else E'\nCancellation: '||trim(p_reason) end
   where id=p_session_id returning * into v_row;
  v_other:=case when v_uid=v_row.mentor_id then v_row.mentee_id else v_row.mentor_id end;
  if v_other is not null then insert into public.notifications(user_id,title,body,ref_table,ref_id) values(v_other,'Mentorship session cancelled','A mentorship session was cancelled.','mentorship_sessions',v_row.id); end if;
  return v_row;
end;
$$;

create or replace function public.complete_mentorship_session(p_session_id uuid, p_notes text default null)
returns public.mentorship_sessions
language plpgsql security definer set search_path=''
as $$
declare v_uid uuid := (select auth.uid()); v_row public.mentorship_sessions%rowtype;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select * into v_row from public.mentorship_sessions where id=p_session_id for update;
  if not found then raise exception 'session not found'; end if;
  if v_row.mentor_id<>v_uid and not private.is_admin_user() then raise exception 'only mentor or admin can complete a session'; end if;
  if v_row.status<>'scheduled' then raise exception 'session is not scheduled'; end if;
  update public.mentorship_sessions set status='completed',completed_at=now(),updated_at=now(),notes=coalesce(nullif(trim(coalesce(p_notes,'')),''),notes) where id=p_session_id returning * into v_row;
  insert into public.notifications(user_id,title,body,ref_table,ref_id)
  values(v_row.mentee_id,'Mentorship session completed','Your mentorship session was marked complete.','mentorship_sessions',v_row.id);
  return v_row;
end;
$$;

revoke all on function public.cancel_mentorship_request(uuid) from public, anon;
revoke all on function public.respond_mentorship_request(uuid,text) from public, anon;
revoke all on function public.schedule_mentorship_session(uuid,timestamptz,integer,text) from public, anon;
revoke all on function public.cancel_mentorship_session(uuid,text) from public, anon;
revoke all on function public.complete_mentorship_session(uuid,text) from public, anon;
grant execute on function public.cancel_mentorship_request(uuid) to authenticated, service_role;
grant execute on function public.respond_mentorship_request(uuid,text) to authenticated, service_role;
grant execute on function public.schedule_mentorship_session(uuid,timestamptz,integer,text) to authenticated, service_role;
grant execute on function public.cancel_mentorship_session(uuid,text) to authenticated, service_role;
grant execute on function public.complete_mentorship_session(uuid,text) to authenticated, service_role;

;
