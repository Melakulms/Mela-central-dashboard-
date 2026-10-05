begin;
do $$
declare u uuid; r jsonb; d date := (now() at time zone 'Africa/Addis_Ababa')::date;
begin
 select id into u from public.profiles where account_status='active' and deleted_at is null limit 1;
 if u is null then raise exception 'No active fixture candidate'; end if;
 if has_function_privilege('authenticated','public.reserve_mela_ai_gateway_attempt(uuid)','execute') or has_function_privilege('anon','public.reserve_mela_ai_gateway_attempt(uuid)','execute') then raise exception 'Browser quota access'; end if;
 delete from private.mela_ai_gateway_usage where usage_day=d;
 update private.mela_ai_gateway_limits set enabled=true,user_daily_limit=2,global_daily_limit=3;
 r:=public.reserve_mela_ai_gateway_attempt(u);if not (r->>'allowed')::boolean then raise exception 'First attempt denied'; end if;
 r:=public.reserve_mela_ai_gateway_attempt(u);if not (r->>'allowed')::boolean then raise exception 'Second attempt denied'; end if;
 r:=public.reserve_mela_ai_gateway_attempt(u);if r->>'code'<>'AI_LIMIT_REACHED' then raise exception 'User quota bypass'; end if;
 if (select attempts from private.mela_ai_gateway_usage where usage_day=d and scope_key='global')<>2 then raise exception 'Denied attempt mutated quota'; end if;
 update private.mela_ai_gateway_limits set user_daily_limit=4,global_daily_limit=2;
 r:=public.reserve_mela_ai_gateway_attempt(u);if r->>'code'<>'AI_LIMIT_REACHED' then raise exception 'Global quota bypass'; end if;
 update private.mela_ai_gateway_limits set enabled=false;
 r:=public.reserve_mela_ai_gateway_attempt(u);if r->>'code'<>'AI_DISABLED' then raise exception 'Disabled gate bypass'; end if;
 r:=public.reserve_mela_ai_gateway_attempt(null);if r->>'code'<>'ACCOUNT_UNAVAILABLE' then raise exception 'Missing identity accepted'; end if;
end $$;
rollback;
