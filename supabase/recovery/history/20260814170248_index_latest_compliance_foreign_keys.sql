-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260814170248
create index if not exists data_protection_incidents_detected_by_idx on public.data_protection_incidents(detected_by);
create index if not exists platform_launch_requirements_completed_by_idx on public.platform_launch_requirements(completed_by);
;
