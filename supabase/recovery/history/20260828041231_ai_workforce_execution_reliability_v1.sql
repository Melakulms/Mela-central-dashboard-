-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260828041231
create index if not exists idx_mela_ai_tasks_parent_status on public.mela_ai_tasks (parent_task_id, status, created_at); create index if not exists idx_mela_ai_tasks_agent_status on public.mela_ai_tasks (assigned_agent_id, status, priority desc, created_at); create index if not exists idx_mela_ai_runs_task_created on public.mela_ai_runs (task_id, created_at desc); create index if not exists idx_mela_ai_runs_agent_status on public.mela_ai_runs (agent_id, status, created_at desc); create index if not exists idx_mela_ai_tool_calls_run_created on public.mela_ai_tool_calls (run_id, created_at desc);
;
