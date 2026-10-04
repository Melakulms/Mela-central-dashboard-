-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20261004090240
-- The existing video switch must guard server writes, not just navigation.
-- Ending/leaving/removal and consent withdrawal remain possible during shutdown.
set lock_timeout='5s';
create or replace function private.enforce_video_shutdown_boundary()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if public.platform_feature_available('video_calls') is true then return new; end if;
  if tg_op='UPDATE' then
    if tg_table_name='video_call_rooms' and new.status in ('ended','cancelled') then return new; end if;
    if tg_table_name='video_call_participants' then
      if new.status in ('left','declined','removed') then return new; end if;
      -- end_video_call also issues harmless no-op updates for nonjoined members.
      if new is not distinct from old then return new; end if;
      if new.recording_consent is false and
        (to_jsonb(new)-array['recording_consent','recording_consented_at']) is not distinct from
        (to_jsonb(old)-array['recording_consent','recording_consented_at']) then return new; end if;
    end if;
  end if;
  raise exception 'Video calls are temporarily disabled' using errcode='42501';
end;
$$;
revoke all on function private.enforce_video_shutdown_boundary() from public,anon,authenticated;
create trigger video_shutdown_rooms before insert or update on public.video_call_rooms
for each row execute function private.enforce_video_shutdown_boundary();
create trigger video_shutdown_participants before insert or update on public.video_call_participants
for each row execute function private.enforce_video_shutdown_boundary();
create trigger video_shutdown_signals before insert or update on public.video_call_signals
for each row execute function private.enforce_video_shutdown_boundary();
create trigger video_shutdown_presence before insert or update on public.video_call_presence
for each row execute function private.enforce_video_shutdown_boundary();

-- A repeated join can be a no-op UPDATE, so guard key disclosure at entry too.
create or replace function private.join_video_call(p_room_id uuid)
returns text language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=(select auth.uid()); v_key text;
begin
  if public.platform_feature_available('video_calls') is not true then
    raise exception 'Video calls are temporarily disabled' using errcode='42501';
  end if;
  if not exists(select 1 from public.video_call_participants p join public.video_call_rooms r on r.id=p.room_id
    where p.room_id=p_room_id and p.user_id=v_uid and p.status in ('accepted','joined') and r.status in ('scheduled','open','live')) then
    raise exception 'video call access required';
  end if;
  update public.video_call_participants set status='joined',joined_at=coalesce(joined_at,now()),left_at=null where room_id=p_room_id and user_id=v_uid;
  update public.video_call_rooms set status='live',started_at=coalesce(started_at,now()),updated_at=now() where id=p_room_id and status in ('scheduled','open');
  select room_key into v_key from public.video_call_rooms where id=p_room_id;
  insert into public.video_call_events(room_id,actor_id,event_type) values(p_room_id,v_uid,'joined');
  return v_key;
end;
$$;

;
