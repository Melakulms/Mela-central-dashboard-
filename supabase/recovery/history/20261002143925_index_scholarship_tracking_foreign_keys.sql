-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20261002143925
create index if not exists scholarship_application_tasks_application_id_fk_idx on public.scholarship_application_tasks (application_id);
create index if not exists scholarship_application_tasks_opportunity_id_fk_idx on public.scholarship_application_tasks (opportunity_id);
create index if not exists scholarship_saved_opportunity_id_fk_idx on public.scholarship_saved (opportunity_id);
;
