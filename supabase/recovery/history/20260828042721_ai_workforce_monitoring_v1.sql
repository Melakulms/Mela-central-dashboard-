-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260828042721
create index if not exists idx_mela_ai_security_events_recent on public.mela_ai_security_events (severity, created_at desc); create index if not exists idx_mela_ai_tasks_failures on public.mela_ai_tasks (status, retry_count, updated_at desc) where status in ('failed','waiting_approval'); create index if not exists idx_mela_ai_runs_failures on public.mela_ai_runs (status, retry_count, created_at desc) where status='failed';
;
