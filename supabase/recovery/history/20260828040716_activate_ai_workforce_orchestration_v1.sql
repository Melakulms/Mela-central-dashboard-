-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260828040716
create index if not exists idx_mela_ai_approvals_task_status on public.mela_ai_approvals (task_id, status, created_at desc); create index if not exists idx_mela_ai_tool_calls_run_status on public.mela_ai_tool_calls (run_id, status, created_at); create index if not exists idx_mela_ai_sessions_agent_status on public.mela_ai_sessions (agent_id, status, updated_at desc); create index if not exists idx_mela_ai_memory_approved_expiry on public.mela_ai_memory (user_id, approved, expires_at);
;
