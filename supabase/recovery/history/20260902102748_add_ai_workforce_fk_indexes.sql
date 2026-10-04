-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260902102748
create index if not exists mela_ai_agent_tools_tool_id_idx on public.mela_ai_agent_tools(tool_id);
create index if not exists mela_ai_approvals_requested_by_idx on public.mela_ai_approvals(requested_by);
create index if not exists mela_ai_approvals_reviewed_by_idx on public.mela_ai_approvals(reviewed_by);
create index if not exists mela_ai_messages_user_id_idx on public.mela_ai_messages(user_id);
create index if not exists mela_ai_runs_session_id_idx on public.mela_ai_runs(session_id);
create index if not exists mela_ai_security_events_user_id_idx on public.mela_ai_security_events(user_id);
create index if not exists mela_ai_tasks_assigned_user_id_idx on public.mela_ai_tasks(assigned_user_id);
create index if not exists mela_ai_tasks_created_by_idx on public.mela_ai_tasks(created_by);
create index if not exists mela_ai_tool_calls_tool_id_idx on public.mela_ai_tool_calls(tool_id);
create index if not exists mela_ai_tool_calls_user_id_idx on public.mela_ai_tool_calls(user_id);
;
