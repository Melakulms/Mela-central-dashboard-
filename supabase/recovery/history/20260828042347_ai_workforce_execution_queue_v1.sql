-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260828042347
create index if not exists idx_mela_ai_tasks_dispatch_queue on public.mela_ai_tasks (status, approval_status, priority desc, created_at asc) where status='queued' and approval_status='not_required'; create index if not exists idx_mela_ai_agents_routing on public.mela_ai_agents (enabled, domain, autonomy_level, created_at); create index if not exists idx_mela_ai_runs_active on public.mela_ai_runs (status, created_at desc) where status in ('queued','running');
;
