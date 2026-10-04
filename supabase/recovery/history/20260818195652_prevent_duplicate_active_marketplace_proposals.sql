-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260818195652
create unique index if not exists marketplace_submissions_one_active_per_user_task_idx
on public.marketplace_submissions (task_id, user_id)
where status <> 'withdrawn';
;
