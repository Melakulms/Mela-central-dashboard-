-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815050504
create index if not exists mela_curriculum_alignments_reviewed_by_idx on public.mela_curriculum_alignments(reviewed_by);
create index if not exists mela_curriculum_objectives_framework_key_idx on public.mela_curriculum_objectives(framework_key);
create index if not exists mela_curriculum_objectives_subject_key_idx on public.mela_curriculum_objectives(subject_key);
create index if not exists mela_education_pilot_cohorts_stage_key_idx on public.mela_education_pilot_cohorts(stage_key);
create index if not exists mela_education_pilot_measurements_metric_key_idx on public.mela_education_pilot_measurements(metric_key);
create index if not exists mela_education_pilot_metrics_metric_key_idx on public.mela_education_pilot_metrics(metric_key);
create index if not exists mela_impact_measurements_measured_by_idx on public.mela_impact_measurements(measured_by);
create index if not exists mela_impact_measurements_reviewed_by_idx on public.mela_impact_measurements(reviewed_by);

create or replace function public.get_mela_education_value_status()
returns jsonb
language plpgsql
stable
security invoker
set search_path to ''
as $$
declare
  v_supported bigint;
  v_measurements bigint;
  v_pilots bigint;
  v_claim_state text;
  v_claim text;
begin
  if not private.is_admin_user() then
    raise exception 'admin access required';
  end if;

  select count(*), count(*) filter (where validation_status='supported')
    into v_measurements, v_supported
  from public.mela_impact_measurements;
  select count(*) into v_pilots from public.mela_education_pilots;

  if v_supported > 0 then
    v_claim_state := 'locally_supported';
    v_claim := 'Reviewed local measurements include supported improvement. Claims must stay scoped to the measured metric, population, period, sample size and methodology.';
  elsif v_measurements > 0 then
    v_claim_state := 'evidence_under_review';
    v_claim := 'Local measurements exist, but Mela does not yet have a reviewed supported impact claim.';
  elsif v_pilots > 0 then
    v_claim_state := 'pilot_evidence_pending';
    v_claim := 'Education pilots exist, but no reviewed local outcome evidence supports an impact claim yet.';
  else
    v_claim_state := 'architecture_ready_evidence_pending';
    v_claim := 'Mela has an education-value architecture, but no locally reviewed impact evidence yet. Do not market educational impact as proven.';
  end if;

  return jsonb_build_object(
    'claim_state', v_claim_state,
    'impact_claim', v_claim,
    'benchmarks', jsonb_build_object(
      'systems', (select count(*) from public.education_benchmark_systems where active),
      'source_practices', (select count(*) from public.education_benchmark_practices where active),
      'adaptations', (select count(*) from public.education_benchmark_adaptations where active),
      'ethiopia_validated_adaptations', (select count(*) from public.education_benchmark_adaptations where active and ethiopia_validation_status='validated'),
      'unvalidated_adaptations', (select count(*) from public.education_benchmark_adaptations where active and coalesce(ethiopia_validation_status,'unvalidated')<>'validated')
    ),
    'curriculum', jsonb_build_object(
      'national_subjects', (select count(*) from public.mela_national_subject_catalog where active),
      'published_objectives', (select count(*) from public.mela_curriculum_objectives where content_status='published'),
      'officially_mapped_objectives', (select count(*) from public.mela_curriculum_objectives where official_alignment_status not in ('not_officially_mapped','unmapped','pending')),
      'framework_alignments', (select count(*) from public.mela_curriculum_alignments where active),
      'reviewed_alignments', (select count(*) from public.mela_curriculum_alignments where active and reviewed_at is not null)
    ),
    'evidence', jsonb_build_object(
      'outcome_metrics', (select count(*) from public.mela_outcome_metrics where active),
      'pilots', v_pilots,
      'active_pilots', (select count(*) from public.mela_education_pilots where status='active'),
      'pilot_measurements', (select count(*) from public.mela_education_pilot_measurements),
      'impact_measurements', v_measurements,
      'supported_impact_measurements', v_supported,
      'learning_interventions', (select count(*) from public.mela_learning_interventions),
      'completed_interventions_with_outcome', (select count(*) from public.mela_learning_interventions where status='completed' and outcome_score is not null)
    ),
    'launch', jsonb_build_object(
      'required_total', (select count(*) from public.platform_launch_requirements where required),
      'required_complete', (select count(*) from public.platform_launch_requirements where required and manual_status='complete'),
      'required_blocked', (select count(*) from public.platform_launch_requirements where required and manual_status='blocked'),
      'required_pending', (select count(*) from public.platform_launch_requirements where required and coalesce(manual_status,'pending') not in ('complete','blocked','not_required'))
    ),
    'guardrails', jsonb_build_object(
      'local_validation_required', true,
      'human_curriculum_review_required', true,
      'privacy_thresholds_enforced', true,
      'no_impact_claim_without_supported_measurement', true
    )
  );
end;
$$;

revoke all on function public.get_mela_education_value_status() from public, anon;
grant execute on function public.get_mela_education_value_status() to authenticated, service_role;

create or replace function public.create_education_pilot(
  p_partner_organization_id uuid,
  p_title text,
  p_description text,
  p_stage_keys text[],
  p_evaluation_design text,
  p_start_date date,
  p_end_date date,
  p_minimum_sample_size integer,
  p_consent_and_ethics_note text,
  p_methodology_note text
)
returns uuid
language plpgsql
security invoker
set search_path to ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_id uuid;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if not (private.is_admin_user() or private.has_sector_partner_membership(p_partner_organization_id,v_uid,true)) then
    raise exception 'verified education partner access required';
  end if;
  if not exists(select 1 from public.sector_partner_organizations where id=p_partner_organization_id and partner_type_key in ('school','college_tvet','university')) then
    raise exception 'school, college/TVET or university partner required';
  end if;
  if nullif(trim(coalesce(p_title,'')),'') is null then raise exception 'pilot title is required'; end if;
  if p_evaluation_design not in ('before_after','matched_comparison','stepped_rollout','descriptive') then raise exception 'invalid evaluation design'; end if;
  if coalesce(p_minimum_sample_size,0) < 10 then raise exception 'minimum sample size must be at least 10'; end if;
  if p_stage_keys is null or cardinality(p_stage_keys)=0 then raise exception 'at least one education stage is required'; end if;
  if exists(select 1 from unnest(p_stage_keys) x where not exists(select 1 from public.education_audience_stages s where s.stage_key=x)) then raise exception 'invalid education stage'; end if;
  if p_end_date is not null and p_start_date is not null and p_end_date < p_start_date then raise exception 'end date cannot be before start date'; end if;
  if nullif(trim(coalesce(p_consent_and_ethics_note,'')),'') is null then raise exception 'consent and ethics note is required'; end if;
  if nullif(trim(coalesce(p_methodology_note,'')),'') is null then raise exception 'methodology note is required'; end if;

  insert into public.mela_education_pilots(
    partner_organization_id,title,description,stage_keys,evaluation_design,status,start_date,end_date,
    minimum_sample_size,consent_and_ethics_note,methodology_note,created_by
  ) values (
    p_partner_organization_id,trim(p_title),nullif(trim(coalesce(p_description,'')),''),p_stage_keys,p_evaluation_design,'draft',p_start_date,p_end_date,
    p_minimum_sample_size,trim(p_consent_and_ethics_note),trim(p_methodology_note),v_uid
  ) returning id into v_id;
  return v_id;
end;
$$;

revoke all on function public.create_education_pilot(uuid,text,text,text[],text,date,date,integer,text,text) from public, anon;
grant execute on function public.create_education_pilot(uuid,text,text,text[],text,date,date,integer,text,text) to authenticated, service_role;

create or replace function public.add_education_pilot_cohort(
  p_pilot_id uuid,
  p_cohort_key text,
  p_title text,
  p_cohort_type text,
  p_stage_key text,
  p_grade_level smallint,
  p_target_sample_size integer
)
returns uuid
language plpgsql
security invoker
set search_path to ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_org uuid;
  v_id uuid;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select partner_organization_id into v_org from public.mela_education_pilots where id=p_pilot_id;
  if v_org is null then raise exception 'pilot not found'; end if;
  if not (private.is_admin_user() or private.has_sector_partner_membership(v_org,v_uid,true)) then raise exception 'pilot write access required'; end if;
  if nullif(trim(coalesce(p_cohort_key,'')),'') is null or nullif(trim(coalesce(p_title,'')),'') is null then raise exception 'cohort key and title are required'; end if;
  if p_cohort_type not in ('intervention','comparison','rollout_later') then raise exception 'invalid cohort type'; end if;
  if p_stage_key is not null and not exists(select 1 from public.education_audience_stages where stage_key=p_stage_key) then raise exception 'invalid education stage'; end if;
  if p_grade_level is not null and (p_grade_level < 1 or p_grade_level > 12) then raise exception 'grade level must be 1-12'; end if;
  if p_target_sample_size is not null and p_target_sample_size < 1 then raise exception 'target sample size must be positive'; end if;

  insert into public.mela_education_pilot_cohorts(pilot_id,cohort_key,title,cohort_type,stage_key,grade_level,target_sample_size)
  values(p_pilot_id,trim(p_cohort_key),trim(p_title),p_cohort_type,p_stage_key,p_grade_level,p_target_sample_size)
  on conflict(pilot_id,cohort_key) do update set title=excluded.title,cohort_type=excluded.cohort_type,stage_key=excluded.stage_key,grade_level=excluded.grade_level,target_sample_size=excluded.target_sample_size
  returning id into v_id;
  return v_id;
end;
$$;

revoke all on function public.add_education_pilot_cohort(uuid,text,text,text,text,smallint,integer) from public, anon;
grant execute on function public.add_education_pilot_cohort(uuid,text,text,text,text,smallint,integer) to authenticated, service_role;

create or replace function public.set_education_pilot_metric(
  p_pilot_id uuid,
  p_metric_key text,
  p_primary_metric boolean,
  p_target_value numeric,
  p_notes text
)
returns jsonb
language plpgsql
security invoker
set search_path to ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_org uuid;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select partner_organization_id into v_org from public.mela_education_pilots where id=p_pilot_id;
  if v_org is null then raise exception 'pilot not found'; end if;
  if not (private.is_admin_user() or private.has_sector_partner_membership(v_org,v_uid,true)) then raise exception 'pilot write access required'; end if;
  if not exists(select 1 from public.mela_outcome_metrics where metric_key=p_metric_key and active) then raise exception 'active outcome metric required'; end if;

  insert into public.mela_education_pilot_metrics(pilot_id,metric_key,primary_metric,target_value,notes)
  values(p_pilot_id,p_metric_key,coalesce(p_primary_metric,false),p_target_value,nullif(trim(coalesce(p_notes,'')),''))
  on conflict(pilot_id,metric_key) do update set primary_metric=excluded.primary_metric,target_value=excluded.target_value,notes=excluded.notes;

  return jsonb_build_object('pilot_id',p_pilot_id,'metric_key',p_metric_key,'primary_metric',coalesce(p_primary_metric,false),'target_value',p_target_value);
end;
$$;

revoke all on function public.set_education_pilot_metric(uuid,text,boolean,numeric,text) from public, anon;
grant execute on function public.set_education_pilot_metric(uuid,text,boolean,numeric,text) to authenticated, service_role;

create or replace function public.record_education_pilot_measurement(
  p_pilot_id uuid,
  p_cohort_id uuid,
  p_metric_key text,
  p_measurement_period text,
  p_measured_on date,
  p_value numeric,
  p_sample_size integer,
  p_methodology text,
  p_evidence_note text,
  p_data_quality text
)
returns uuid
language plpgsql
security invoker
set search_path to ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_org uuid;
  v_threshold integer;
  v_id uuid;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select partner_organization_id into v_org from public.mela_education_pilots where id=p_pilot_id;
  if v_org is null then raise exception 'pilot not found'; end if;
  if not (private.is_admin_user() or private.has_sector_partner_membership(v_org,v_uid,true)) then raise exception 'pilot write access required'; end if;
  if not exists(select 1 from public.mela_education_pilot_cohorts where id=p_cohort_id and pilot_id=p_pilot_id) then raise exception 'cohort does not belong to pilot'; end if;
  if not exists(select 1 from public.mela_education_pilot_metrics where pilot_id=p_pilot_id and metric_key=p_metric_key) then raise exception 'metric is not assigned to pilot'; end if;
  if p_measurement_period not in ('baseline','midline','endline','followup') then raise exception 'invalid measurement period'; end if;
  if p_data_quality not in ('provisional','reviewed','verified','invalid') then raise exception 'invalid data quality'; end if;
  select privacy_threshold into v_threshold from public.mela_outcome_metrics where metric_key=p_metric_key and active;
  if v_threshold is null then raise exception 'active outcome metric required'; end if;
  if coalesce(p_sample_size,0) < v_threshold then raise exception 'sample size % is below privacy/evidence threshold %',coalesce(p_sample_size,0),v_threshold; end if;
  if p_measured_on is null then raise exception 'measurement date required'; end if;
  if nullif(trim(coalesce(p_methodology,'')),'') is null then raise exception 'methodology required'; end if;

  insert into public.mela_education_pilot_measurements(pilot_id,cohort_id,metric_key,measurement_period,measured_on,value,sample_size,methodology,evidence_note,data_quality,recorded_by)
  values(p_pilot_id,p_cohort_id,p_metric_key,p_measurement_period,p_measured_on,p_value,p_sample_size,trim(p_methodology),nullif(trim(coalesce(p_evidence_note,'')),''),p_data_quality,v_uid)
  on conflict(pilot_id,cohort_id,metric_key,measurement_period,measured_on) do update set value=excluded.value,sample_size=excluded.sample_size,methodology=excluded.methodology,evidence_note=excluded.evidence_note,data_quality=excluded.data_quality,recorded_by=excluded.recorded_by
  returning id into v_id;
  return v_id;
end;
$$;

revoke all on function public.record_education_pilot_measurement(uuid,uuid,text,text,date,numeric,integer,text,text,text) from public, anon;
grant execute on function public.record_education_pilot_measurement(uuid,uuid,text,text,date,numeric,integer,text,text,text) to authenticated, service_role;

create or replace function public.set_education_pilot_status(p_pilot_id uuid,p_status text)
returns jsonb
language plpgsql
security invoker
set search_path to ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_org uuid;
  v_missing_primary bigint;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select partner_organization_id into v_org from public.mela_education_pilots where id=p_pilot_id;
  if v_org is null then raise exception 'pilot not found'; end if;
  if not (private.is_admin_user() or private.has_sector_partner_membership(v_org,v_uid,true)) then raise exception 'pilot write access required'; end if;
  if p_status not in ('draft','recruiting','active','completed','paused','cancelled') then raise exception 'invalid pilot status'; end if;

  if p_status in ('active','completed') then
    if not exists(select 1 from public.mela_education_pilot_cohorts where pilot_id=p_pilot_id) then raise exception 'add at least one pilot cohort first'; end if;
    if not exists(select 1 from public.mela_education_pilot_metrics where pilot_id=p_pilot_id) then raise exception 'assign at least one outcome metric first'; end if;
  end if;

  if p_status='completed' then
    if not exists(select 1 from public.mela_education_pilot_metrics where pilot_id=p_pilot_id and primary_metric) then raise exception 'mark at least one primary outcome metric before completion'; end if;
    select count(*) into v_missing_primary
    from public.mela_education_pilot_metrics pm
    where pm.pilot_id=p_pilot_id and pm.primary_metric and (
      not exists(select 1 from public.mela_education_pilot_measurements m where m.pilot_id=p_pilot_id and m.metric_key=pm.metric_key and m.measurement_period='baseline' and m.data_quality in ('reviewed','verified'))
      or not exists(select 1 from public.mela_education_pilot_measurements m where m.pilot_id=p_pilot_id and m.metric_key=pm.metric_key and m.measurement_period='endline' and m.data_quality in ('reviewed','verified'))
    );
    if v_missing_primary > 0 then raise exception 'every primary metric requires reviewed/verified baseline and endline measurements before completion'; end if;
  end if;

  update public.mela_education_pilots set status=p_status,updated_at=now() where id=p_pilot_id;
  return jsonb_build_object('pilot_id',p_pilot_id,'status',p_status);
end;
$$;

revoke all on function public.set_education_pilot_status(uuid,text) from public, anon;
grant execute on function public.set_education_pilot_status(uuid,text) to authenticated, service_role;

create or replace function public.get_my_education_pilots()
returns jsonb
language plpgsql
stable
security invoker
set search_path to ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',p.id,'partner_organization_id',p.partner_organization_id,'title',p.title,'description',p.description,'stage_keys',p.stage_keys,
      'evaluation_design',p.evaluation_design,'status',p.status,'start_date',p.start_date,'end_date',p.end_date,'minimum_sample_size',p.minimum_sample_size,
      'consent_and_ethics_note',p.consent_and_ethics_note,'methodology_note',p.methodology_note,
      'cohorts',coalesce((select jsonb_agg(to_jsonb(c) order by c.created_at) from public.mela_education_pilot_cohorts c where c.pilot_id=p.id),'[]'::jsonb),
      'metrics',coalesce((select jsonb_agg(jsonb_build_object('metric_key',pm.metric_key,'title',om.title,'unit',om.unit,'primary_metric',pm.primary_metric,'target_value',pm.target_value,'privacy_threshold',om.privacy_threshold,'notes',pm.notes) order by pm.primary_metric desc,om.title) from public.mela_education_pilot_metrics pm join public.mela_outcome_metrics om on om.metric_key=pm.metric_key where pm.pilot_id=p.id),'[]'::jsonb),
      'measurements',coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'cohort_id',m.cohort_id,'metric_key',m.metric_key,'measurement_period',m.measurement_period,'measured_on',m.measured_on,'value',m.value,'sample_size',m.sample_size,'data_quality',m.data_quality,'evidence_note',m.evidence_note) order by m.measured_on,m.measurement_period) from public.mela_education_pilot_measurements m where m.pilot_id=p.id),'[]'::jsonb)
    ) order by p.created_at desc)
    from public.mela_education_pilots p
  ),'[]'::jsonb);
end;
$$;

revoke all on function public.get_my_education_pilots() from public, anon;
grant execute on function public.get_my_education_pilots() to authenticated, service_role;
;
