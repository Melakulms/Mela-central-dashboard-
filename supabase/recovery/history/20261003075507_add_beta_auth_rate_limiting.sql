-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20261003075507
create table if not exists private.beta_auth_rate_limits (
  key_hash text primary key,
  window_started_at timestamptz not null default now(),
  hit_count integer not null default 0 check (hit_count >= 0),
  updated_at timestamptz not null default now()
);

revoke all on table private.beta_auth_rate_limits from public, anon, authenticated;

create or replace function public.consume_beta_auth_rate_limit(
  p_key_hash text,
  p_limit integer,
  p_window_seconds integer
)
returns boolean
language plpgsql
security definer
set search_path to 'private','pg_temp'
as $function$
declare
  v_allowed boolean;
  v_now timestamptz := clock_timestamp();
begin
  if p_key_hash is null or length(p_key_hash) <> 64 then
    return false;
  end if;
  if p_limit < 1 or p_limit > 1000 or p_window_seconds < 10 or p_window_seconds > 86400 then
    return false;
  end if;

  insert into private.beta_auth_rate_limits(key_hash, window_started_at, hit_count, updated_at)
  values (p_key_hash, v_now, 1, v_now)
  on conflict (key_hash) do update
  set
    hit_count = case
      when beta_auth_rate_limits.window_started_at <= v_now - make_interval(secs => p_window_seconds)
        then 1
      else beta_auth_rate_limits.hit_count + 1
    end,
    window_started_at = case
      when beta_auth_rate_limits.window_started_at <= v_now - make_interval(secs => p_window_seconds)
        then v_now
      else beta_auth_rate_limits.window_started_at
    end,
    updated_at = v_now
  returning hit_count <= p_limit into v_allowed;

  if random() < 0.01 then
    delete from private.beta_auth_rate_limits
    where updated_at < v_now - interval '7 days';
  end if;

  return coalesce(v_allowed, false);
end;
$function$;

revoke all on function public.consume_beta_auth_rate_limit(text, integer, integer) from public, anon, authenticated;
grant execute on function public.consume_beta_auth_rate_limit(text, integer, integer) to service_role;

;
