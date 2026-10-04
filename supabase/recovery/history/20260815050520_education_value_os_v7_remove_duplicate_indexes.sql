-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815050520
drop index if exists public.mela_curriculum_objectives_framework_key_idx;
drop index if exists public.mela_curriculum_objectives_subject_key_idx;
drop index if exists public.mela_education_pilot_cohorts_stage_key_idx;
drop index if exists public.mela_education_pilot_measurements_metric_key_idx;
drop index if exists public.mela_education_pilot_metrics_metric_key_idx;
;
