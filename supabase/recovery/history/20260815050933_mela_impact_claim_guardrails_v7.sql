-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815050933
create unique index if not exists mela_impact_measurements_pilot_cohort_metric_uidx
on public.mela_impact_measurements(pilot_id,cohort_id,metric_key)
where pilot_id is not null and cohort_id is not null;

create or replace function public.admin_build_pilot_impact_summary(
  p_pilot_id uuid,
  p_cohort_id uuid,
  p_metric_key text
)
returns uuid
language plpgsql
set search_path=''
as $$
declare
  v_pilot public.mela_education_pilots%rowtype;
  v_cohort public.mela_education_pilot_cohorts%rowtype;
  v_base public.mela_education_pilot_measurements%rowtype;
  v_end public.mela_education_pilot_measurements%rowtype;
  v_id uuid;
  v_threshold integer;
begin
  if not private.is_admin_user() then raise exception 'admin access required'; end if;
  select * into v_pilot from public.mela_education_pilots where id=p_pilot_id;
  if not found then raise exception 'pilot not found'; end if;
  select * into v_cohort from public.mela_education_pilot_cohorts where id=p_cohort_id and pilot_id=p_pilot_id;
  if not found then raise exception 'cohort does not belong to pilot'; end if;
  if not exists(select 1 from public.mela_education_pilot_metrics where pilot_id=p_pilot_id and metric_key=p_metric_key) then raise exception 'metric is not assigned to pilot'; end if;
  select privacy_threshold into v_threshold from public.mela_outcome_metrics where metric_key=p_metric_key and active;
  if v_threshold is null then raise exception 'active metric required'; end if;
  select * into v_base from public.mela_education_pilot_measurements where pilot_id=p_pilot_id and cohort_id=p_cohort_id and metric_key=p_metric_key and measurement_period='baseline' and data_quality='verified' order by measured_on asc,created_at asc limit 1;
  if not found then raise exception 'Founder/Admin-verified baseline measurement required'; end if;
  select * into v_end from public.mela_education_pilot_measurements where pilot_id=p_pilot_id and cohort_id=p_cohort_id and metric_key=p_metric_key and measurement_period in ('endline','followup') and data_quality='verified' order by measured_on desc,created_at desc limit 1;
  if not found then raise exception 'Founder/Admin-verified endline or follow-up measurement required'; end if;
  if least(v_base.sample_size,v_end.sample_size) < v_threshold then raise exception 'verified measurement sample is below the metric privacy threshold'; end if;

  select id into v_id from public.mela_impact_measurements where pilot_id=p_pilot_id and cohort_id=p_cohort_id and metric_key=p_metric_key limit 1;
  if v_id is null then
    insert into public.mela_impact_measurements(partner_organization_id,pilot_id,cohort_id,metric_key,stage_key,period_start,period_end,sample_size,baseline_value,end_value,methodology,evidence_note,source_reference,validation_status,measured_by,review_note)
    values(v_pilot.partner_organization_id,p_pilot_id,p_cohort_id,p_metric_key,v_cohort.stage_key,v_base.measured_on,v_end.measured_on,least(v_base.sample_size,v_end.sample_size),v_base.value,v_end.value,concat('Pilot design: ',v_pilot.evaluation_design,'. Pilot methodology: ',coalesce(v_pilot.methodology_note,'—'),'. Baseline: ',v_base.methodology,'. Endline/follow-up: ',v_end.methodology),concat_ws(' | ',nullif(v_base.evidence_note,''),nullif(v_end.evidence_note,'')),'pilot:'||p_pilot_id::text,'reviewed',(select auth.uid()),'Generated from Founder/Admin-verified pilot baseline and endline/follow-up measurements; final interpretation still requires explicit review.') returning id into v_id;
  else
    update public.mela_impact_measurements set
      partner_organization_id=v_pilot.partner_organization_id,stage_key=v_cohort.stage_key,
      period_start=v_base.measured_on,period_end=v_end.measured_on,sample_size=least(v_base.sample_size,v_end.sample_size),
      baseline_value=v_base.value,end_value=v_end.value,
      methodology=concat('Pilot design: ',v_pilot.evaluation_design,'. Pilot methodology: ',coalesce(v_pilot.methodology_note,'—'),'. Baseline: ',v_base.methodology,'. Endline/follow-up: ',v_end.methodology),
      evidence_note=concat_ws(' | ',nullif(v_base.evidence_note,''),nullif(v_end.evidence_note,'')),
      source_reference='pilot:'||p_pilot_id::text,validation_status='reviewed',review_note='Refreshed from current Founder/Admin-verified baseline and endline/follow-up evidence; interpretation requires review.',reviewed_by=null,reviewed_at=null,updated_at=now()
    where id=v_id;
  end if;
  return v_id;
end;
$$;

create or replace function public.admin_review_education_impact(
  p_measurement_id uuid,
  p_decision text,
  p_review_note text
)
returns jsonb
language plpgsql
set search_path=''
as $$
declare
  v_row public.mela_impact_measurements%rowtype;
  v_threshold integer;
  v_metric_title text;
  v_direction text;
  v_verified_base integer;
  v_verified_end integer;
  v_pilot_status text;
  v_org_status text;
begin
  if not private.is_admin_user() then raise exception 'admin access required'; end if;
  if p_decision not in ('supported','inconclusive','rejected') then raise exception 'decision must be supported, inconclusive or rejected'; end if;
  if nullif(trim(coalesce(p_review_note,'')),'') is null then raise exception 'review note is required'; end if;
  select * into v_row from public.mela_impact_measurements where id=p_measurement_id for update;
  if not found then raise exception 'impact summary not found'; end if;
  select privacy_threshold,title,direction into v_threshold,v_metric_title,v_direction from public.mela_outcome_metrics where metric_key=v_row.metric_key;
  if p_decision='supported' then
    if v_row.pilot_id is null or v_row.cohort_id is null then raise exception 'supported impact requires a linked Mela education pilot and cohort'; end if;
    select status into v_pilot_status from public.mela_education_pilots where id=v_row.pilot_id;
    if v_pilot_status <> 'completed' then raise exception 'supported impact requires a completed pilot'; end if;
    select verification_status into v_org_status from public.sector_partner_organizations where id=v_row.partner_organization_id;
    if v_org_status <> 'verified' then raise exception 'supported impact requires a verified education partner'; end if;
    if v_row.sample_size < coalesce(v_threshold,10) then raise exception 'sample size % is below threshold %',v_row.sample_size,coalesce(v_threshold,10); end if;
    if v_row.baseline_value is null or v_row.end_value is null then raise exception 'baseline and end values are required'; end if;
    if v_direction='higher_better' and v_row.end_value <= v_row.baseline_value then raise exception 'this higher-is-better metric did not improve from baseline'; end if;
    if v_direction='lower_better' and v_row.end_value >= v_row.baseline_value then raise exception 'this lower-is-better metric did not improve from baseline'; end if;
    select count(*) into v_verified_base from public.mela_education_pilot_measurements where pilot_id=v_row.pilot_id and cohort_id=v_row.cohort_id and metric_key=v_row.metric_key and measurement_period='baseline' and data_quality='verified';
    select count(*) into v_verified_end from public.mela_education_pilot_measurements where pilot_id=v_row.pilot_id and cohort_id=v_row.cohort_id and metric_key=v_row.metric_key and measurement_period in ('endline','followup') and data_quality='verified';
    if v_verified_base=0 or v_verified_end=0 then raise exception 'supported impact requires Founder/Admin-verified baseline and endline/follow-up pilot measurements'; end if;
  end if;
  update public.mela_impact_measurements set validation_status=p_decision,review_note=trim(p_review_note),reviewed_by=(select auth.uid()),reviewed_at=now(),updated_at=now() where id=p_measurement_id;
  return jsonb_build_object('id',p_measurement_id,'metric_key',v_row.metric_key,'metric_title',v_metric_title,'decision',p_decision,'sample_size',v_row.sample_size,'privacy_threshold',coalesce(v_threshold,10),'direction',v_direction,'pilot_id',v_row.pilot_id,'cohort_id',v_row.cohort_id);
end;
$$;

create or replace function public.admin_education_system_snapshot()
returns jsonb
language plpgsql
stable
set search_path=''
as $$
begin
  if not private.is_admin_user() then raise exception 'admin access required'; end if;
  return jsonb_build_object(
    'generated_at',now(),
    'benchmark',jsonb_build_object('countries',(select count(*) from public.education_benchmark_systems where active),'source_practices',(select count(*) from public.education_benchmark_practices where active),'adaptations',(select count(*) from public.education_benchmark_adaptations where active),'locally_supported_adaptations',(select count(*) from public.education_benchmark_adaptations where active and ethiopia_validation_status='supported'),'adaptation_status',(select coalesce(jsonb_object_agg(implementation_status,cnt),'{}'::jsonb) from (select implementation_status,count(*) cnt from public.education_benchmark_adaptations where active group by implementation_status)s),'local_validation_status',(select coalesce(jsonb_object_agg(ethiopia_validation_status,cnt),'{}'::jsonb) from (select ethiopia_validation_status,count(*) cnt from public.education_benchmark_adaptations where active group by ethiopia_validation_status)s),'engines',(select jsonb_object_agg(implementation_status,cnt) from (select implementation_status,count(*) cnt from public.mela_education_engines group by implementation_status)s)),
    'curriculum',jsonb_build_object('official_subject_listings',(select count(*) from public.mela_national_subject_catalog where active),'published_objectives',(select count(*) from public.mela_curriculum_objectives where content_status='published'),'resource_links',(select count(*) from public.mela_curriculum_resource_links where active),'school_resource_links',(select count(*) from public.mela_curriculum_resource_links r join public.mela_curriculum_objectives o on o.id=r.objective_id where r.active and o.stage_key like 'school_%'),'bridge_rows',(select count(*) from public.mela_curriculum_alignments where active),'approved_mappings',(select count(*) from public.mela_curriculum_alignments where active and review_status='approved'),'local_challenges',(select count(*) from public.mela_local_challenge_templates where active),'approved_or_pilot_challenges',(select count(*) from public.mela_local_challenge_templates where active and content_status in ('approved','pilot'))),
    'learners',jsonb_build_object('with_stage',(select count(*) from public.profiles where education_stage_key is not null),'by_stage',(select coalesce(jsonb_object_agg(education_stage_key,cnt),'{}'::jsonb) from (select education_stage_key,count(*) cnt from public.profiles where education_stage_key is not null group by education_stage_key)s),'mastery_records',(select count(*) from public.learner_mastery_records),'active_catchup_plans',(select count(*) from public.learner_catchup_plans where status='active'),'projects',(select count(*) from public.learner_projects),'verified_projects',(select count(*) from public.learner_projects where verified)),
    'educators',jsonb_build_object('profiles',(select count(*) from public.educator_profiles),'classrooms',(select count(*) from public.educator_classrooms),'copilot_requests',(select count(*) from public.educator_copilot_requests)),
    'institutions',jsonb_build_object('education_partners',(select count(*) from public.sector_partner_organizations where partner_type_key in ('school','college_tvet','university')),'verified_education_partners',(select count(*) from public.sector_partner_organizations where partner_type_key in ('school','college_tvet','university') and verification_status='verified'),'outcome_snapshots',(select count(*) from public.institution_outcome_snapshots),'education_pilots',(select count(*) from public.mela_education_pilots),'active_or_completed_pilots',(select count(*) from public.mela_education_pilots where status in ('active','completed')),'verified_pilot_measurements',(select count(*) from public.mela_education_pilot_measurements where data_quality='verified'),'reviewed_impact_summaries',(select count(*) from public.mela_impact_measurements where validation_status in ('reviewed','supported','inconclusive','rejected')),'supported_impact_measurements',(select count(*) from public.mela_impact_measurements where validation_status='supported'),'defined_metrics',(select count(*) from public.mela_outcome_metrics where active)),
    'offline',jsonb_build_object('published_packs',(select count(*) from public.mela_offline_content_packs where published),'sync_states',(select count(*) from public.learner_offline_sync_state))
  );
end;
$$;

-- v4 remains as a compatibility alias; v5 is canonical.
create or replace function public.admin_education_value_readiness_v4()
returns jsonb language sql stable set search_path='' as $$ select public.admin_education_value_readiness_v5(); $$;

revoke all on function public.admin_education_system_snapshot() from public,anon;
grant execute on function public.admin_education_system_snapshot() to authenticated,service_role;
revoke all on function public.admin_education_value_readiness_v4() from public,anon;
grant execute on function public.admin_education_value_readiness_v4() to authenticated,service_role;
;
