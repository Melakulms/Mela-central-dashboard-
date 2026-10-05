-- Provider-attempt limits, shared by every caller of the OpenAI gateway.
-- Failed/ambiguous attempts consume capacity: never retry around the budget.
create table private.mela_ai_gateway_limits (
 singleton boolean primary key default true check(singleton),
 enabled boolean not null default true,
 user_daily_limit integer not null default 10 check(user_daily_limit between 0 and 100),
 global_daily_limit integer not null default 100 check(global_daily_limit between 0 and 10000)
);
insert into private.mela_ai_gateway_limits(singleton) values(true);
create table private.mela_ai_gateway_usage (
 usage_day date not null,
 scope_key text not null,
 attempts integer not null default 0 check(attempts >= 0),
 primary key(usage_day,scope_key)
);
alter table private.mela_ai_gateway_limits enable row level security;
alter table private.mela_ai_gateway_usage enable row level security;
revoke all on private.mela_ai_gateway_limits,private.mela_ai_gateway_usage from public,anon,authenticated;
grant select,update on private.mela_ai_gateway_limits to service_role;
grant select,insert,update on private.mela_ai_gateway_usage to service_role;
create or replace function public.reserve_mela_ai_gateway_attempt(p_user_id uuid)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare
 cfg private.mela_ai_gateway_limits%rowtype;
 d date := (now() at time zone 'Africa/Addis_Ababa')::date;
 g integer;
 u integer;
begin
 if p_user_id is null or not exists(select 1 from public.profiles where id=p_user_id and account_status='active' and deleted_at is null) then
   return jsonb_build_object('allowed',false,'code','ACCOUNT_UNAVAILABLE');
 end if;
 -- One lock order across all requests prevents quota races and deadlocks.
 select * into cfg from private.mela_ai_gateway_limits where singleton for update;
 if not found or not cfg.enabled then return jsonb_build_object('allowed',false,'code','AI_DISABLED'); end if;
 insert into private.mela_ai_gateway_usage(usage_day,scope_key) values(d,'global'),(d,p_user_id::text) on conflict do nothing;
 select attempts into g from private.mela_ai_gateway_usage where usage_day=d and scope_key='global';
 select attempts into u from private.mela_ai_gateway_usage where usage_day=d and scope_key=p_user_id::text;
 if g>=cfg.global_daily_limit or u>=cfg.user_daily_limit then return jsonb_build_object('allowed',false,'code','AI_LIMIT_REACHED'); end if;
 update private.mela_ai_gateway_usage set attempts=attempts+1 where usage_day=d and scope_key in ('global',p_user_id::text);
 return jsonb_build_object('allowed',true,'remaining',cfg.user_daily_limit-u-1);
end $$;
revoke all on function public.reserve_mela_ai_gateway_attempt(uuid) from public,anon,authenticated;
grant execute on function public.reserve_mela_ai_gateway_attempt(uuid) to service_role;
