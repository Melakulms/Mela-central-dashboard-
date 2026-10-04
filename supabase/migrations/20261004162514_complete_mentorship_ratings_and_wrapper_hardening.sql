-- Phase 5 mentorship completion: ratings plus current admin authority and invoker wrappers.

alter table public.mentor_profiles
  add column if not exists rating_average numeric(3,2) not null default 0,
  add column if not exists rating_count integer not null default 0;

alter table public.mentor_profiles
  drop constraint if exists mentor_profiles_rating_average_check,
  add constraint mentor_profiles_rating_average_check check (rating_average >= 0 and rating_average <= 5),
  drop constraint if exists mentor_profiles_rating_count_check,
  add constraint mentor_profiles_rating_count_check check (rating_count >= 0);

-- Replace legacy profile-role admin bypasses with the MFA-backed admin registry helper.
drop policy if exists "Mentors update own profile" on public.mentor_profiles;
create policy "Mentors update own profile"
on public.mentor_profiles
for update
to authenticated
using (user_id = (select auth.uid()) or private.is_admin_user())
with check (user_id = (select auth.uid()) or private.is_admin_user());

drop policy if exists "Mentors delete own profile" on public.mentor_profiles;
create policy "Mentors delete own profile"
on public.mentor_profiles
for delete
to authenticated
using (user_id = (select auth.uid()) or private.is_admin_user());

create table if not exists public.mentorship_ratings (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null unique references public.mentorship_sessions(id) on delete restrict,
  mentor_id uuid not null references public.profiles(id) on delete restrict,
  mentee_id uuid not null references public.profiles(id) on delete restrict,
  rating smallint not null check (rating between 1 and 5),
  comment text,
  created_at timestamptz not null default now(),
  constraint mentorship_ratings_comment_length check (comment is null or char_length(comment) <= 2000),
  constraint mentorship_ratings_distinct_participants check (mentor_id <> mentee_id)
);

alter table public.mentorship_ratings enable row level security;

revoke all on table public.mentorship_ratings from public, anon, authenticated;
grant select on table public.mentorship_ratings to authenticated;

create policy "Mentorship ratings readable by session participants"
on public.mentorship_ratings
for select
to authenticated
using (
  mentor_id = (select auth.uid())
  or mentee_id = (select auth.uid())
  or private.is_admin_user()
);

create index if not exists mentorship_ratings_mentor_created_idx
  on public.mentorship_ratings(mentor_id, created_at desc);
create index if not exists mentorship_ratings_mentee_created_idx
  on public.mentorship_ratings(mentee_id, created_at desc);

create or replace function private.refresh_mentor_rating_summary(p_mentor_id uuid)
returns void
language sql
security definer
set search_path to ''
as $function$
  update public.mentor_profiles m
  set rating_average = coalesce((
        select round(avg(r.rating)::numeric, 2)
        from public.mentorship_ratings r
        where r.mentor_id = p_mentor_id
      ), 0),
      rating_count = (
        select count(*)::integer
        from public.mentorship_ratings r
        where r.mentor_id = p_mentor_id
      ),
      updated_at = now()
  where m.user_id = p_mentor_id;
$function$;

create or replace function private.refresh_mentor_rating_summary_trigger()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  perform private.refresh_mentor_rating_summary(coalesce(new.mentor_id, old.mentor_id));
  return coalesce(new, old);
end;
$function$;

drop trigger if exists trg_refresh_mentor_rating_summary on public.mentorship_ratings;
create trigger trg_refresh_mentor_rating_summary
after insert or delete on public.mentorship_ratings
for each row execute function private.refresh_mentor_rating_summary_trigger();

create or replace function private.rate_mentorship_session(
  p_session_id uuid,
  p_rating smallint,
  p_comment text default null
)
returns public.mentorship_ratings
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_session public.mentorship_sessions%rowtype;
  v_row public.mentorship_ratings%rowtype;
  v_comment text := nullif(btrim(coalesce(p_comment, '')), '');
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if p_rating is null or p_rating < 1 or p_rating > 5 then raise exception 'rating must be 1 to 5'; end if;
  if v_comment is not null and char_length(v_comment) > 2000 then raise exception 'rating comment is too long'; end if;

  select * into v_session
  from public.mentorship_sessions
  where id = p_session_id
  for share;

  if not found then raise exception 'mentorship session not found'; end if;
  if v_session.status <> 'completed' or v_session.completed_at is null then
    raise exception 'only completed mentorship sessions can be rated';
  end if;
  if v_session.mentee_id <> v_uid then
    raise exception 'only the mentee can rate this mentorship session';
  end if;
  if v_session.mentor_id is null or v_session.mentor_id = v_uid then
    raise exception 'invalid mentorship participants';
  end if;

  insert into public.mentorship_ratings(session_id, mentor_id, mentee_id, rating, comment)
  values(v_session.id, v_session.mentor_id, v_uid, p_rating, v_comment)
  on conflict(session_id) do nothing
  returning * into v_row;

  if v_row.id is null then raise exception 'this mentorship session has already been rated'; end if;

  perform private.create_notification(
    v_session.mentor_id,
    'New mentorship rating',
    'A completed mentorship session received a learner rating.',
    'mentorship_sessions',
    v_session.id
  );

  return v_row;
end;
$function$;

revoke all on function private.rate_mentorship_session(uuid,smallint,text) from public, anon;
grant execute on function private.rate_mentorship_session(uuid,smallint,text) to authenticated, service_role;

create or replace function public.rate_mentorship_session(
  p_session_id uuid,
  p_rating smallint,
  p_comment text default null
)
returns public.mentorship_ratings
language sql
security invoker
set search_path to ''
as $function$
  select * from private.rate_mentorship_session(p_session_id,p_rating,p_comment);
$function$;
revoke all on function public.rate_mentorship_session(uuid,smallint,text) from public, anon;
grant execute on function public.rate_mentorship_session(uuid,smallint,text) to authenticated, service_role;

-- Existing private implementations already enforce participant/admin ownership.
-- Public API wrappers should not themselves inherit owner privileges.
create or replace function public.respond_mentorship_request(p_request_id uuid,p_decision text)
returns public.mentorship_requests
language sql
security invoker
set search_path to ''
as $function$
  select * from private.respond_mentorship_request(p_request_id,p_decision);
$function$;

create or replace function public.schedule_mentorship_session(
  p_request_id uuid,
  p_scheduled_at timestamptz,
  p_duration_min integer default 30,
  p_call_room_id text default null
)
returns public.mentorship_sessions
language sql
security invoker
set search_path to ''
as $function$
  select * from private.schedule_mentorship_session(p_request_id,p_scheduled_at,p_duration_min,p_call_room_id);
$function$;

create or replace function public.cancel_mentorship_session(p_session_id uuid,p_reason text default null)
returns public.mentorship_sessions
language sql
security invoker
set search_path to ''
as $function$
  select * from private.cancel_mentorship_session(p_session_id,p_reason);
$function$;

create or replace function public.complete_mentorship_session(p_session_id uuid,p_notes text default null)
returns public.mentorship_sessions
language sql
security invoker
set search_path to ''
as $function$
  select * from private.complete_mentorship_session(p_session_id,p_notes);
$function$;

revoke all on function private.respond_mentorship_request(uuid,text) from public, anon;
revoke all on function private.schedule_mentorship_session(uuid,timestamptz,integer,text) from public, anon;
revoke all on function private.cancel_mentorship_session(uuid,text) from public, anon;
revoke all on function private.complete_mentorship_session(uuid,text) from public, anon;
grant execute on function private.respond_mentorship_request(uuid,text) to authenticated, service_role;
grant execute on function private.schedule_mentorship_session(uuid,timestamptz,integer,text) to authenticated, service_role;
grant execute on function private.cancel_mentorship_session(uuid,text) to authenticated, service_role;
grant execute on function private.complete_mentorship_session(uuid,text) to authenticated, service_role;

revoke all on function public.respond_mentorship_request(uuid,text) from public, anon;
revoke all on function public.schedule_mentorship_session(uuid,timestamptz,integer,text) from public, anon;
revoke all on function public.cancel_mentorship_session(uuid,text) from public, anon;
revoke all on function public.complete_mentorship_session(uuid,text) from public, anon;
grant execute on function public.respond_mentorship_request(uuid,text) to authenticated, service_role;
grant execute on function public.schedule_mentorship_session(uuid,timestamptz,integer,text) to authenticated, service_role;
grant execute on function public.cancel_mentorship_session(uuid,text) to authenticated, service_role;
grant execute on function public.complete_mentorship_session(uuid,text) to authenticated, service_role;
