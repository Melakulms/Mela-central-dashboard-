-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260813090556
do $$
declare r record;
begin
  for r in
    select tablename
    from pg_tables
    where schemaname='public'
      and tablename not in ('platform_feature_flags','platform_announcements')
  loop
    execute format('alter table public.%I enable row level security',r.tablename);
    execute format('drop policy if exists mela_gate_platform_live on public.%I',r.tablename);
    execute format(
      'create policy mela_gate_platform_live on public.%I as restrictive for all to anon, authenticated using (public.platform_feature_available(%L)) with check (public.platform_feature_available(%L))',
      r.tablename,'platform_live','platform_live'
    );
  end loop;
end $$;
;
