-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260823070443
create index if not exists data_subject_requests_admin_queue_idx on public.data_subject_requests(status, requested_at desc);
create index if not exists data_protection_incidents_admin_queue_idx on public.data_protection_incidents(status, severity, detected_at desc);
create index if not exists platform_operational_alerts_admin_queue_idx on public.platform_operational_alerts(status, severity, last_seen_at desc);
;
