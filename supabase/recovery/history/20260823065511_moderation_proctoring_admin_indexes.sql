-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260823065511
create index if not exists reports_admin_queue_idx on public.reports(status, created_at desc);
create index if not exists proctor_reviews_admin_queue_idx on public.proctor_reviews(decision, created_at desc);
create index if not exists assessment_attempts_proctor_queue_idx on public.assessment_attempts(proctor_status, reviewed_at desc, started_at desc);
create index if not exists arena_integrity_events_admin_queue_idx on public.arena_integrity_events(severity, created_at desc);
create index if not exists arena_matches_integrity_queue_idx on public.arena_matches(integrity_required, status, created_at desc);
;
