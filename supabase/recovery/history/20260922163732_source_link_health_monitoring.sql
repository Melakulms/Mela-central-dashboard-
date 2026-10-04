-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260922163732
alter table public.global_opportunity_sources
  add column if not exists action_page_http_status integer,
  add column if not exists action_page_http_checked_at timestamptz,
  add column if not exists action_page_http_ok boolean;

create index if not exists global_opportunity_sources_http_queue_idx
  on public.global_opportunity_sources (active, verification_status, action_page_verification_status, action_page_http_checked_at);

create or replace function private.refresh_global_source_link_health(p_batch_size integer default 10)
returns integer
language plpgsql
security definer
set search_path = public, extensions, pg_catalog
as $$
declare
  r record;
  v_status integer;
  v_ok boolean;
  v_count integer := 0;
begin
  if p_batch_size < 1 or p_batch_size > 50 then
    raise exception 'batch size must be between 1 and 50';
  end if;

  for r in
    select id, coalesce(application_url, base_url) as url
    from public.global_opportunity_sources
    where active
      and verification_status = 'verified'
      and coalesce(application_url, base_url) is not null
      and (
        action_page_http_checked_at is null
        or action_page_http_checked_at < now() - interval '24 hours'
      )
    order by action_page_http_checked_at nulls first
    limit p_batch_size
  loop
    begin
      select status into v_status from extensions.http_get(r.url);
      v_ok := v_status between 200 and 399;

      update public.global_opportunity_sources
      set action_page_http_status = v_status,
          action_page_http_checked_at = now(),
          action_page_http_ok = v_ok,
          last_checked_at = now(),
          updated_at = now()
      where id = r.id;

      v_count := v_count + 1;
    exception when others then
      update public.global_opportunity_sources
      set action_page_http_status = null,
          action_page_http_checked_at = now(),
          action_page_http_ok = false,
          last_checked_at = now(),
          updated_at = now()
      where id = r.id;

      v_count := v_count + 1;
    end;
  end loop;

  return v_count;
end;
$$;

revoke all on function private.refresh_global_source_link_health(integer) from public, anon, authenticated;
grant execute on function private.refresh_global_source_link_health(integer) to service_role;

select cron.schedule(
  'mela-source-link-health',
  '*/30 * * * *',
  $$select private.refresh_global_source_link_health(10);$$
);
;
