-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815105039
create or replace function private.expire_stale_global_sources_v12()
returns integer language plpgsql security definer set search_path='' as $$declare n integer; begin
 update public.global_opportunity_sources set verification_status='stale',active=false,updated_at=now(),evidence_note=concat_ws(' ',evidence_note,'Automatically hidden after 45 days without re-verification.') where verification_status='verified' and verified_at < now()-interval '45 days'; get diagnostics n=row_count; return n; end $$;
revoke all on function private.expire_stale_global_sources_v12() from public,anon,authenticated;
grant execute on function private.expire_stale_global_sources_v12() to service_role;

do $$declare j bigint; begin
 select jobid into j from cron.job where jobname='mela-global-source-freshness-v12' limit 1; if j is not null then perform cron.unschedule(j); end if;
 perform cron.schedule('mela-global-source-freshness-v12','23 3 * * *',$c$select private.expire_stale_global_sources_v12();$c$);
end$$;
;
