-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815050327
create index if not exists mela_curriculum_objectives_framework_idx on public.mela_curriculum_objectives(framework_key);
create index if not exists mela_curriculum_objectives_subject_idx on public.mela_curriculum_objectives(subject_key);
create index if not exists mela_education_pilot_cohorts_stage_idx on public.mela_education_pilot_cohorts(stage_key);
create index if not exists mela_education_pilot_measurements_metric_idx on public.mela_education_pilot_measurements(metric_key);
create index if not exists mela_education_pilot_metrics_metric_idx on public.mela_education_pilot_metrics(metric_key);
create index if not exists mela_curriculum_alignments_reviewed_by_idx on public.mela_curriculum_alignments(reviewed_by);
create index if not exists mela_impact_measurements_measured_by_idx on public.mela_impact_measurements(measured_by);
create index if not exists mela_impact_measurements_reviewed_by_idx on public.mela_impact_measurements(reviewed_by);
;
