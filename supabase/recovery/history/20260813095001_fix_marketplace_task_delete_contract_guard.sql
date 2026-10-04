-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260813095001
drop policy if exists "Employer teams delete marketplace tasks" on public.marketplace_tasks;
create policy "Employer teams delete marketplace tasks"
on public.marketplace_tasks
for delete
to authenticated
using (
  (private.has_employer_access(employer_id, true) or private.is_admin_user())
  and status in ('draft','open','cancelled','expired')
  and not exists (
    select 1 from public.freelance_contracts c
    where c.task_id = marketplace_tasks.id
  )
);
;
