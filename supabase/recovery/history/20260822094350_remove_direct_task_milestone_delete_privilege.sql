-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260822094350
revoke delete on public.task_milestones from authenticated;
;
