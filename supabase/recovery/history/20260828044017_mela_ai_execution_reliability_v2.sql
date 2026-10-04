-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260828044017
create index if not exists idx_mela_ai_tasks_ready_for_dispatch on public.mela_ai_tasks (priority desc, created_at asc) where status='queued' and approval_status='not_required'; create index if not exists idx_mela_ai_tasks_waiting_approval on public.mela_ai_tasks (created_at desc) where status='waiting_approval'; create index if not exists idx_mela_ai_runs_verification_pending on public.mela_ai_runs (created_at desc) where verification_status='pending';
;
