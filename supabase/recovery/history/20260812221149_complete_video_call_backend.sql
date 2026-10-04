-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812221149
create table if not exists public.video_call_rooms (
  id uuid primary key default gen_random_uuid(),
  room_key text not null unique default lower(substr(md5(gen_random_uuid()::text||clock_timestamp()::text),1,24)),
  title text,
  room_type text not null default 'direct' check(room_type in ('direct','mentorship','interview','freelance','arena')),
  reference_id uuid,
  created_by uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'scheduled' check(status in ('scheduled','open','live','ended','cancelled')),
  scheduled_at timestamptz,
  started_at timestamptz,
  ended_at timestamptz,
  max_participants integer not null default 10 check(max_participants between 2 and 100),
  recording_consent_required boolean not null default true,
  recording_status text not null default 'off' check(recording_status in ('off','requested','consented','recording','completed','failed')),
  recording_path text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(room_type,reference_id)
);
create table if not exists public.video_call_participants (
  room_id uuid not null references public.video_call_rooms(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  participant_role text not null default 'guest' check(participant_role in ('host','guest','mentor','mentee','interviewer','candidate','freelancer','employer','arena_player')),
  status text not null default 'invited' check(status in ('invited','accepted','joined','left','declined','removed')),
  invited_by uuid references public.profiles(id) on delete set null,
  invited_at timestamptz not null default now(), accepted_at timestamptz, joined_at timestamptz, left_at timestamptz,
  primary key(room_id,user_id)
);
create table if not exists public.video_call_events (
  id uuid primary key default gen_random_uuid(), room_id uuid not null references public.video_call_rooms(id) on delete cascade,
  actor_id uuid references public.profiles(id) on delete set null,
  event_type text not null check(event_type in ('created','invited','accepted','declined','joined','left','started','ended','cancelled','recording_requested','recording_consented','recording_started','recording_stopped','removed')),
  details jsonb not null default '{}'::jsonb, created_at timestamptz not null default now()
);
create table if not exists public.video_call_signals (
  id uuid primary key default gen_random_uuid(), room_id uuid not null references public.video_call_rooms(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  recipient_id uuid references public.profiles(id) on delete cascade,
  signal_type text not null check(signal_type in ('offer','answer','ice_candidate','renegotiate','hangup')),
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(), expires_at timestamptz not null default (now()+interval '10 minutes')
);
create table if not exists public.video_call_presence (
  room_id uuid not null references public.video_call_rooms(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  device_id text not null default 'default',
  state jsonb not null default '{}'::jsonb,
  joined_at timestamptz not null default now(), last_seen_at timestamptz not null default now(),
  primary key(room_id,user_id,device_id)
);

alter table public.mentorship_sessions add column if not exists video_call_room_id uuid references public.video_call_rooms(id) on delete set null;
alter table public.interviews add column if not exists video_call_room_id uuid references public.video_call_rooms(id) on delete set null;
alter table public.freelance_contracts add column if not exists video_call_room_id uuid references public.video_call_rooms(id) on delete set null;
alter table public.arena_matches add column if not exists video_call_room_id uuid references public.video_call_rooms(id) on delete set null;

create index if not exists video_call_rooms_creator_status_idx on public.video_call_rooms(created_by,status,scheduled_at);
create index if not exists video_call_participants_user_status_idx on public.video_call_participants(user_id,status);
create index if not exists video_call_events_room_created_idx on public.video_call_events(room_id,created_at desc);
create index if not exists video_call_signals_room_created_idx on public.video_call_signals(room_id,created_at);
create index if not exists video_call_signals_expiry_idx on public.video_call_signals(expires_at);
create index if not exists video_call_presence_user_idx on public.video_call_presence(user_id,last_seen_at desc);
create index if not exists mentorship_sessions_video_call_idx on public.mentorship_sessions(video_call_room_id);
create index if not exists interviews_video_call_idx on public.interviews(video_call_room_id);
create index if not exists freelance_contracts_video_call_idx on public.freelance_contracts(video_call_room_id);
create index if not exists arena_matches_video_call_idx on public.arena_matches(video_call_room_id);

alter table public.video_call_rooms enable row level security;
alter table public.video_call_participants enable row level security;
alter table public.video_call_events enable row level security;
alter table public.video_call_signals enable row level security;
alter table public.video_call_presence enable row level security;
revoke all on public.video_call_rooms,public.video_call_participants,public.video_call_events,public.video_call_signals,public.video_call_presence from anon,authenticated;
grant select on public.video_call_rooms,public.video_call_participants,public.video_call_events,public.video_call_signals,public.video_call_presence to authenticated;
grant insert on public.video_call_signals,public.video_call_presence to authenticated;
grant update(state,last_seen_at) on public.video_call_presence to authenticated;
grant delete on public.video_call_signals,public.video_call_presence to authenticated;
grant all on public.video_call_rooms,public.video_call_participants,public.video_call_events,public.video_call_signals,public.video_call_presence to service_role;

create or replace function private.can_access_video_room(p_room_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.video_call_participants p where p.room_id=p_room_id and p.user_id=(select auth.uid()) and p.status in ('accepted','joined')) or private.is_admin_user(); $$;

drop policy if exists "Video call rooms participant read" on public.video_call_rooms;
create policy "Video call rooms participant read" on public.video_call_rooms for select to authenticated using(created_by=(select auth.uid()) or exists(select 1 from public.video_call_participants p where p.room_id=id and p.user_id=(select auth.uid())) or private.is_admin_user());
drop policy if exists "Video call participants participant read" on public.video_call_participants;
create policy "Video call participants participant read" on public.video_call_participants for select to authenticated using(user_id=(select auth.uid()) or private.can_access_video_room(room_id) or private.is_admin_user());
drop policy if exists "Video call events participant read" on public.video_call_events;
create policy "Video call events participant read" on public.video_call_events for select to authenticated using(private.can_access_video_room(room_id) or exists(select 1 from public.video_call_participants p where p.room_id=video_call_events.room_id and p.user_id=(select auth.uid())) or private.is_admin_user());
drop policy if exists "Video call signals participant read" on public.video_call_signals;
create policy "Video call signals participant read" on public.video_call_signals for select to authenticated using(private.can_access_video_room(room_id) and (recipient_id is null or recipient_id=(select auth.uid()) or sender_id=(select auth.uid())) and expires_at>now());
drop policy if exists "Video call signals participant send" on public.video_call_signals;
create policy "Video call signals participant send" on public.video_call_signals for insert to authenticated with check(sender_id=(select auth.uid()) and private.can_access_video_room(room_id) and (recipient_id is null or exists(select 1 from public.video_call_participants p where p.room_id=video_call_signals.room_id and p.user_id=recipient_id and p.status in ('accepted','joined'))));
drop policy if exists "Video call signals sender delete" on public.video_call_signals;
create policy "Video call signals sender delete" on public.video_call_signals for delete to authenticated using(sender_id=(select auth.uid()));
drop policy if exists "Video presence room read" on public.video_call_presence;
create policy "Video presence room read" on public.video_call_presence for select to authenticated using(private.can_access_video_room(room_id));
drop policy if exists "Video presence self insert" on public.video_call_presence;
create policy "Video presence self insert" on public.video_call_presence for insert to authenticated with check(user_id=(select auth.uid()) and private.can_access_video_room(room_id));
drop policy if exists "Video presence self update" on public.video_call_presence;
create policy "Video presence self update" on public.video_call_presence for update to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()) and private.can_access_video_room(room_id));
drop policy if exists "Video presence self delete" on public.video_call_presence;
create policy "Video presence self delete" on public.video_call_presence for delete to authenticated using(user_id=(select auth.uid()));

create or replace function private.create_direct_video_call(p_title text,p_scheduled_at timestamptz,p_max_participants int)
returns public.video_call_rooms language plpgsql security definer set search_path=''
as $$ declare v_uid uuid:=(select auth.uid()); v public.video_call_rooms; begin
 if v_uid is null then raise exception 'authentication required'; end if;
 insert into public.video_call_rooms(title,room_type,created_by,status,scheduled_at,max_participants) values(p_title,'direct',v_uid,case when p_scheduled_at is null or p_scheduled_at<=now() then 'open' else 'scheduled' end,p_scheduled_at,greatest(2,least(coalesce(p_max_participants,10),100))) returning * into v;
 insert into public.video_call_participants(room_id,user_id,participant_role,status,invited_by,accepted_at) values(v.id,v_uid,'host','accepted',v_uid,now());
 insert into public.video_call_events(room_id,actor_id,event_type) values(v.id,v_uid,'created'); return v; end $$;
create or replace function public.create_direct_video_call(p_title text default null,p_scheduled_at timestamptz default null,p_max_participants int default 10) returns public.video_call_rooms language sql security invoker set search_path='' as $$ select private.create_direct_video_call(p_title,p_scheduled_at,p_max_participants); $$;

create or replace function private.ensure_video_call_room(p_reference_type text,p_reference_id uuid)
returns public.video_call_rooms language plpgsql security definer set search_path=''
as $$ declare v_uid uuid:=(select auth.uid()); v public.video_call_rooms; v_sched timestamptz; begin
 if v_uid is null then raise exception 'authentication required'; end if;
 if p_reference_type not in ('mentorship','interview','freelance','arena') then raise exception 'unsupported call reference'; end if;
 select * into v from public.video_call_rooms where room_type=p_reference_type and reference_id=p_reference_id;
 if v.id is not null then if not exists(select 1 from public.video_call_participants p where p.room_id=v.id and p.user_id=v_uid) and v.created_by<>v_uid and not private.is_admin_user() then raise exception 'video room access denied'; end if; return v; end if;
 if p_reference_type='mentorship' then select scheduled_at into v_sched from public.mentorship_sessions where id=p_reference_id and (mentor_id=v_uid or mentee_id=v_uid); if not found then raise exception 'mentorship access required'; end if;
 elsif p_reference_type='interview' then select i.starts_at into v_sched from public.interviews i join public.applications a on a.id=i.application_id join public.opportunities o on o.id=a.opportunity_id where i.id=p_reference_id and (a.applicant_id=v_uid or private.has_employer_access(o.employer_id,false) or private.is_admin_user()); if not found then raise exception 'interview access required'; end if;
 elsif p_reference_type='freelance' then select c.started_at into v_sched from public.freelance_contracts c where c.id=p_reference_id and (c.freelancer_id=v_uid or private.has_employer_access(c.employer_id,false) or private.is_admin_user()); if not found then raise exception 'freelance access required'; end if;
 else select coalesce(m.scheduled_at,now()) into v_sched from public.arena_matches m where m.id=p_reference_id and (m.creator_id=v_uid or exists(select 1 from public.arena_participants p where p.match_id=m.id and p.user_id=v_uid) or private.is_admin_user()); if not found then raise exception 'arena access required'; end if; end if;
 insert into public.video_call_rooms(title,room_type,reference_id,created_by,status,scheduled_at,max_participants) values(initcap(p_reference_type)||' video call',p_reference_type,p_reference_id,v_uid,case when v_sched is null or v_sched<=now() then 'open' else 'scheduled' end,v_sched,case when p_reference_type='arena' then 100 else 20 end) returning * into v;
 insert into public.video_call_participants(room_id,user_id,participant_role,status,invited_by,accepted_at) values(v.id,v_uid,'host','accepted',v_uid,now()) on conflict do nothing;
 if p_reference_type='mentorship' then
   insert into public.video_call_participants(room_id,user_id,participant_role,status,invited_by,accepted_at) select v.id,mentor_id,'mentor','accepted',v_uid,now() from public.mentorship_sessions where id=p_reference_id on conflict do nothing;
   insert into public.video_call_participants(room_id,user_id,participant_role,status,invited_by,accepted_at) select v.id,mentee_id,'mentee','accepted',v_uid,now() from public.mentorship_sessions where id=p_reference_id on conflict do nothing;
   update public.mentorship_sessions set video_call_room_id=v.id,call_room_id=v.room_key where id=p_reference_id;
 elsif p_reference_type='interview' then
   insert into public.video_call_participants(room_id,user_id,participant_role,status,invited_by,accepted_at) select v.id,a.applicant_id,'candidate','accepted',v_uid,now() from public.interviews i join public.applications a on a.id=i.application_id where i.id=p_reference_id on conflict do nothing;
   update public.interviews set video_call_room_id=v.id,meeting_url='mela-call:'||v.room_key where id=p_reference_id;
 elsif p_reference_type='freelance' then
   insert into public.video_call_participants(room_id,user_id,participant_role,status,invited_by,accepted_at) select v.id,c.freelancer_id,'freelancer','accepted',v_uid,now() from public.freelance_contracts c where c.id=p_reference_id on conflict do nothing;
   update public.freelance_contracts set video_call_room_id=v.id where id=p_reference_id;
 else
   insert into public.video_call_participants(room_id,user_id,participant_role,status,invited_by,accepted_at) select v.id,p.user_id,'arena_player','accepted',v_uid,now() from public.arena_participants p where p.match_id=p_reference_id and p.status in ('joined','active','finished') on conflict do nothing;
   update public.arena_matches set video_call_room_id=v.id where id=p_reference_id;
 end if;
 insert into public.video_call_events(room_id,actor_id,event_type,details) values(v.id,v_uid,'created',jsonb_build_object('reference_type',p_reference_type,'reference_id',p_reference_id)); return v; end $$;
create or replace function public.ensure_video_call_room(p_reference_type text,p_reference_id uuid) returns public.video_call_rooms language sql security invoker set search_path='' as $$ select private.ensure_video_call_room(p_reference_type,p_reference_id); $$;

create or replace function private.invite_video_call_participant(p_room_id uuid,p_user_id uuid,p_role text)
returns public.video_call_participants language plpgsql security definer set search_path=''
as $$ declare v_uid uuid:=(select auth.uid()); v public.video_call_participants; begin
 if not exists(select 1 from public.video_call_participants p where p.room_id=p_room_id and p.user_id=v_uid and p.participant_role='host' and p.status in ('accepted','joined')) and not private.is_admin_user() then raise exception 'call host access required'; end if;
 if (select count(*) from public.video_call_participants where room_id=p_room_id and status not in ('declined','removed')) >= (select max_participants from public.video_call_rooms where id=p_room_id) then raise exception 'call room is full'; end if;
 insert into public.video_call_participants(room_id,user_id,participant_role,status,invited_by) values(p_room_id,p_user_id,coalesce(p_role,'guest'),'invited',v_uid) on conflict(room_id,user_id) do update set status='invited',participant_role=excluded.participant_role,invited_by=v_uid,invited_at=now(),accepted_at=null,left_at=null returning * into v;
 insert into public.video_call_events(room_id,actor_id,event_type,details) values(p_room_id,v_uid,'invited',jsonb_build_object('user_id',p_user_id)); perform private.create_notification(p_user_id,'Video call invitation','You have been invited to a Mela video call.','video_call_rooms',p_room_id); return v; end $$;
create or replace function public.invite_video_call_participant(p_room_id uuid,p_user_id uuid,p_role text default 'guest') returns public.video_call_participants language sql security invoker set search_path='' as $$ select private.invite_video_call_participant(p_room_id,p_user_id,p_role); $$;

create or replace function private.respond_video_call_invite(p_room_id uuid,p_accept boolean) returns void language plpgsql security definer set search_path=''
as $$ declare v_uid uuid:=(select auth.uid()); begin update public.video_call_participants set status=case when p_accept then 'accepted' else 'declined' end,accepted_at=case when p_accept then now() else null end where room_id=p_room_id and user_id=v_uid and status='invited'; if not found then raise exception 'pending call invitation not found'; end if; insert into public.video_call_events(room_id,actor_id,event_type) values(p_room_id,v_uid,case when p_accept then 'accepted' else 'declined' end); end $$;
create or replace function public.respond_video_call_invite(p_room_id uuid,p_accept boolean) returns void language sql security invoker set search_path='' as $$ select private.respond_video_call_invite(p_room_id,p_accept); $$;

create or replace function private.join_video_call(p_room_id uuid) returns text language plpgsql security definer set search_path=''
as $$ declare v_uid uuid:=(select auth.uid()); v_key text; begin if not exists(select 1 from public.video_call_participants p join public.video_call_rooms r on r.id=p.room_id where p.room_id=p_room_id and p.user_id=v_uid and p.status in ('accepted','joined') and r.status in ('scheduled','open','live')) then raise exception 'video call access required'; end if; update public.video_call_participants set status='joined',joined_at=coalesce(joined_at,now()),left_at=null where room_id=p_room_id and user_id=v_uid; update public.video_call_rooms set status='live',started_at=coalesce(started_at,now()),updated_at=now() where id=p_room_id and status in ('scheduled','open'); select room_key into v_key from public.video_call_rooms where id=p_room_id; insert into public.video_call_events(room_id,actor_id,event_type) values(p_room_id,v_uid,'joined'); return v_key; end $$;
create or replace function public.join_video_call(p_room_id uuid) returns text language sql security invoker set search_path='' as $$ select private.join_video_call(p_room_id); $$;

create or replace function private.leave_video_call(p_room_id uuid) returns void language plpgsql security definer set search_path=''
as $$ declare v_uid uuid:=(select auth.uid()); begin update public.video_call_participants set status='left',left_at=now() where room_id=p_room_id and user_id=v_uid and status='joined'; if not found then raise exception 'joined participant not found'; end if; delete from public.video_call_presence where room_id=p_room_id and user_id=v_uid; insert into public.video_call_events(room_id,actor_id,event_type) values(p_room_id,v_uid,'left'); end $$;
create or replace function public.leave_video_call(p_room_id uuid) returns void language sql security invoker set search_path='' as $$ select private.leave_video_call(p_room_id); $$;

create or replace function private.end_video_call(p_room_id uuid) returns void language plpgsql security definer set search_path=''
as $$ declare v_uid uuid:=(select auth.uid()); begin if not exists(select 1 from public.video_call_rooms r left join public.video_call_participants p on p.room_id=r.id and p.user_id=v_uid where r.id=p_room_id and (r.created_by=v_uid or p.participant_role='host')) and not private.is_admin_user() then raise exception 'call host access required'; end if; update public.video_call_rooms set status='ended',ended_at=now(),updated_at=now() where id=p_room_id and status not in ('ended','cancelled'); update public.video_call_participants set status=case when status='joined' then 'left' else status end,left_at=case when status='joined' then now() else left_at end where room_id=p_room_id; delete from public.video_call_presence where room_id=p_room_id; insert into public.video_call_events(room_id,actor_id,event_type) values(p_room_id,v_uid,'ended'); end $$;
create or replace function public.end_video_call(p_room_id uuid) returns void language sql security invoker set search_path='' as $$ select private.end_video_call(p_room_id); $$;

-- Add signaling/presence tables to Supabase Realtime publication for Postgres Changes subscriptions.
do $$ begin
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='video_call_signals') then alter publication supabase_realtime add table public.video_call_signals; end if;
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='video_call_presence') then alter publication supabase_realtime add table public.video_call_presence; end if;
end $$;

-- Cleanup transient signaling rows every 5 minutes.
create or replace function private.cleanup_video_call_transients() returns integer language plpgsql security definer set search_path=''
as $$ declare v_count int; begin delete from public.video_call_signals where expires_at<now(); get diagnostics v_count=row_count; delete from public.video_call_presence where last_seen_at<now()-interval '2 minutes'; return v_count; end $$;
do $$ declare v_job bigint; begin select jobid into v_job from cron.job where jobname='mela-video-call-cleanup' limit 1; if v_job is not null then perform cron.unschedule(v_job); end if; perform cron.schedule('mela-video-call-cleanup','*/5 * * * *','select private.cleanup_video_call_transients();'); end $$;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('call-recordings','call-recordings',false,1073741824,array['video/webm','video/mp4','audio/webm','audio/mpeg']) on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists "Call recordings participant read" on storage.objects;
create policy "Call recordings participant read" on storage.objects for select to authenticated using(bucket_id='call-recordings' and (storage.foldername(name))[1] is not null and private.can_access_video_room(((storage.foldername(name))[1])::uuid));
drop policy if exists "Call recordings host upload" on storage.objects;
create policy "Call recordings host upload" on storage.objects for insert to authenticated with check(bucket_id='call-recordings' and (storage.foldername(name))[1] is not null and exists(select 1 from public.video_call_participants p where p.room_id=((storage.foldername(name))[1])::uuid and p.user_id=(select auth.uid()) and p.participant_role='host' and p.status in ('accepted','joined')));

do $$ declare r record; begin for r in select n.nspname,p.proname,pg_get_function_identity_arguments(p.oid) args from pg_proc p join pg_namespace n on n.oid=p.pronamespace where (n.nspname='public' and p.proname in ('create_direct_video_call','ensure_video_call_room','invite_video_call_participant','respond_video_call_invite','join_video_call','leave_video_call','end_video_call')) or (n.nspname='private' and p.proname in ('create_direct_video_call','ensure_video_call_room','invite_video_call_participant','respond_video_call_invite','join_video_call','leave_video_call','end_video_call')) loop execute format('revoke all on function %I.%I(%s) from public,anon',r.nspname,r.proname,r.args); execute format('grant execute on function %I.%I(%s) to authenticated,service_role',r.nspname,r.proname,r.args); end loop; end $$;
;
