-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260813102557
alter table public.marketplace_tasks drop constraint if exists marketplace_task_status_chk; alter table public.marketplace_tasks add constraint marketplace_task_status_chk check (status = any (array['draft'::text,'open'::text,'assigned'::text,'awarded'::text,'in_progress'::text,'completed'::text,'cancelled'::text,'disputed'::text,'expired'::text]));
;
