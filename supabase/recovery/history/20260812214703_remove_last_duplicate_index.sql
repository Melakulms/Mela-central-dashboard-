-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812214703
drop index if exists public.platform_events_name_time_idx;
;
