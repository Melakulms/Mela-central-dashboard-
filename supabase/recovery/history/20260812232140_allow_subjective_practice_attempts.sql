-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812232140
alter table public.practice_attempts alter column is_correct drop not null;
;
