begin;
do $test$
declare
  u uuid:=gen_random_uuid(); v uuid:=gen_random_uuid(); event_id uuid:=gen_random_uuid();
  badge uuid; balance integer; blocked boolean;
begin
  insert into auth.users(id,email,raw_app_meta_data,raw_user_meta_data,email_confirmed_at,created_at,updated_at)
  values(u,u::text||'@example.invalid','{"provider":"email"}','{"full_name":"Ledger fixture","role":"student"}',now(),now(),now()),
        (v,v::text||'@example.invalid','{"provider":"email"}','{"full_name":"Outsider fixture","role":"student"}',now(),now(),now());
  execute 'set local role service_role';
  perform public.record_coin_event(event_id,u,10,'Test award');
  perform public.record_coin_event(event_id,u,10,'Test award');
  select coin_balance into balance from public.profiles where id=u;
  if balance<>10 then raise exception 'duplicate event changed balance'; end if;
  blocked:=false;
  begin perform public.record_coin_event(event_id,u,20,'Test award');
  exception when invalid_parameter_value then blocked:=true; end;
  if not blocked then raise exception 'mismatched replay accepted'; end if;
  blocked:=false;
  begin perform public.record_coin_event(gen_random_uuid(),u,-11,'Overspend');
  exception when check_violation then blocked:=true; end;
  if not blocked then raise exception 'negative balance allowed'; end if;
  select coin_balance into balance from public.profiles where id=u;
  if balance<>10 then raise exception 'failed debit changed balance'; end if;
  perform public.record_coin_event(gen_random_uuid(),u,-10,'Spend available coins');
  select coin_balance into balance from public.profiles where id=u;
  if balance<>0 then raise exception 'valid debit failed'; end if;
  blocked:=false;
  begin update public.coin_transactions set amount=100 where id=event_id;
  exception when check_violation then blocked:=true; end;
  if not blocked then raise exception 'history update accepted'; end if;
  blocked:=false;
  begin delete from public.coin_transactions where id=event_id;
  exception when check_violation then blocked:=true; end;
  if not blocked then raise exception 'history deletion accepted'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  if exists(select 1 from public.coin_transactions where user_id=u) then raise exception 'cross-user ledger disclosure'; end if;
  blocked:=false;
  begin perform public.record_coin_event(gen_random_uuid(),v,999,'Forged award');
  exception when insufficient_privilege then blocked:=true; end;
  if not blocked then raise exception 'learner could mint coins'; end if;
  blocked:=false;
  begin insert into public.coin_transactions(user_id,amount,reason) values(v,999,'Direct forgery');
  exception when insufficient_privilege then blocked:=true; end;
  if not blocked then raise exception 'learner could insert ledger'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims','{}',true);
  insert into public.badges(code,title) values('rollback-'||u::text,'Test badge') returning id into badge;
  insert into public.user_badges(user_id,badge_id) values(u,badge);
  if (select verified_passport_badge_count from public.profiles where id=u)<>1 then raise exception 'badge insert counter failed'; end if;
  update public.user_badges set user_id=v where user_id=u and badge_id=badge;
  if (select verified_passport_badge_count from public.profiles where id=u)<>0
    or (select verified_passport_badge_count from public.profiles where id=v)<>1 then raise exception 'badge reassignment counter failed'; end if;
  delete from public.user_badges where user_id=v and badge_id=badge;
  if (select verified_passport_badge_count from public.profiles where id=v)<>0 then raise exception 'badge deletion counter failed'; end if;
end
$test$;
rollback;
