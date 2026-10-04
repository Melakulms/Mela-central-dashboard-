-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260828040632
create index if not exists idx_mela_ai_agents_enabled_domain on public.mela_ai_agents (enabled, domain); create index if not exists idx_mela_ai_tasks_status_priority_created on public.mela_ai_tasks (status, priority desc, created_at); create index if not exists idx_mela_ai_tasks_agent_status on public.mela_ai_tasks (assigned_agent_id, status, created_at); create index if not exists idx_mela_ai_runs_agent_created on public.mela_ai_runs (agent_id, created_at desc); create index if not exists idx_mela_ai_memory_user_scope on public.mela_ai_memory (user_id, memory_scope, updated_at desc);
;
