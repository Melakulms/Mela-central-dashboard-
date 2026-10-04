-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260813103914
drop function if exists public.submit_task_milestone_with_delivery(uuid,text,text);
drop function if exists private.submit_task_milestone_with_delivery(uuid,text,text);
;
