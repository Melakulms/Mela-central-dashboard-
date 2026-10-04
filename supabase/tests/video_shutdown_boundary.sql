begin;
do $test$
declare u uuid:=gen_random_uuid(); v uuid:=gen_random_uuid(); r public.video_call_rooms; blocked boolean;
begin
  insert into auth.users(id,email,raw_app_meta_data,raw_user_meta_data,email_confirmed_at,created_at,updated_at)
  values(u,u::text||'@example.invalid','{"provider":"email"}','{"full_name":"Video host fixture","role":"student"}',now(),now(),now()),
        (v,v::text||'@example.invalid','{"provider":"email"}','{"full_name":"Video guest fixture","role":"student"}',now(),now(),now());
  -- Transaction-only enablement is invisible to other sessions and rolled back.
  update public.platform_feature_flags set enabled=true where feature_key in ('platform_live','video_calls');
  perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  select * into r from public.create_direct_video_call('Rollback video boundary');
  perform public.join_video_call(r.id);
  insert into public.video_call_signals(room_id,sender_id,signal_type) values(r.id,u,'offer');
  insert into public.video_call_presence(room_id,user_id) values(r.id,u);
  execute 'reset role'; perform set_config('request.jwt.claims','{}',true);
  update public.platform_feature_flags set enabled=false where feature_key='video_calls';
  perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  blocked:=false;
  begin perform public.create_direct_video_call('Must fail'); exception when insufficient_privilege then blocked:=true; end;
  if not blocked then raise exception 'disabled room creation accepted'; end if;
  blocked:=false;
  begin perform public.invite_video_call_participant(r.id,v); exception when insufficient_privilege then blocked:=true; end;
  if not blocked then raise exception 'disabled invitation accepted'; end if;
  blocked:=false;
  begin perform public.join_video_call(r.id); exception when insufficient_privilege then blocked:=true; end;
  if not blocked then raise exception 'disabled rejoin disclosed room key'; end if;
  blocked:=false;
  begin perform public.request_video_call_recording(r.id); exception when insufficient_privilege then blocked:=true; end;
  if not blocked then raise exception 'disabled recording request accepted'; end if;
  blocked:=false;
  begin insert into public.video_call_signals(room_id,sender_id,signal_type) values(r.id,u,'offer'); exception when insufficient_privilege then blocked:=true; end;
  if not blocked then raise exception 'disabled signaling accepted'; end if;
  blocked:=false;
  begin insert into public.video_call_presence(room_id,user_id) values(r.id,u); exception when insufficient_privilege then blocked:=true; end;
  if not blocked then raise exception 'disabled presence accepted'; end if;
  execute 'reset role';
  -- Even trusted direct writes must honor shutdown, including UPDATE paths.
  blocked:=false;
  begin update public.video_call_signals set payload='{"retry":true}' where room_id=r.id; exception when insufficient_privilege then blocked:=true; end;
  if not blocked then raise exception 'disabled signal update accepted'; end if;
  blocked:=false;
  begin update public.video_call_presence set last_seen_at=clock_timestamp() where room_id=r.id; exception when insufficient_privilege then blocked:=true; end;
  if not blocked then raise exception 'disabled presence update accepted'; end if;
  execute 'set local role authenticated';
  perform public.leave_video_call(r.id);
  perform public.end_video_call(r.id);
  execute 'reset role'; perform set_config('request.jwt.claims','{}',true);
  if (select status from public.video_call_rooms where id=r.id)<>'ended' then raise exception 'shutdown cleanup blocked'; end if;
end
$test$;
rollback;
select 'PASS: video shutdown blocks create/invite/rejoin/record/signaling/presence and preserves leave/end; fixtures rolled back' as result;
