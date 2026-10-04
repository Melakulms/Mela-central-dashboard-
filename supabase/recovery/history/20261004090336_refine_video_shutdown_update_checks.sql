-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20261004090336
-- Keep table-specific field references inside their own branches.
create or replace function private.enforce_video_shutdown_boundary()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if public.platform_feature_available('video_calls') is true then return new; end if;
  if tg_op='UPDATE' then
    if tg_table_name='video_call_rooms' then
      if new.status in ('ended','cancelled') then return new; end if;
    end if;
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

;
