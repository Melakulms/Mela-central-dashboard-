-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815050749
-- Reconcile Mela's existing pilot protocol with the reviewed impact-summary layer.
-- Raw evidence lives in mela_education_pilot_*; reviewed claims live in mela_impact_measurements.

alter table public.mela_impact_measurements
  add column if not exists pilot_id uuid references public.mela_education_pilots(id) on delete set null,
  add column if not exists cohort_id uuid references public.mela_education_pilot_cohorts(id) on delete set null;
create index if not exists mela_impact_measurements_pilot_idx on public.mela_impact_measurements(pilot_id) where pilot_id is not null;
create index if not exists mela_impact_measurements_cohort_idx on public.mela_impact_measurements(cohort_id) where cohort_id is not null;

-- A partner may record provisional/reviewed measurements, but only Founder/Admin may mark data quality verified.
create or replace function public.record_education_pilot_measurement(
  p_pilot_id uuid, p_cohort_id uuid, p_metric_key text, p_measurement_period text,
  p_measured_on date, p_value numeric, p_sample_size integer, p_methodology text,
  p_evidence_note text, p_data_quality text
)
returns uuid
language plpgsql
set search_path=''
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
  if p_data_quality='verified' and not private.is_admin_user() then raise exception 'only Founder/Admin can mark pilot data verified'; end if;
  select privacy_threshold into v_threshold from public.mela_outcome_metrics where metric_key=p_metric_key and active;
  if v_threshold is null then raise exception 'active outcome metric required'; end if;
  if coalesce(p_sample_size,0) < v_threshold then raise exception 'sample size % is below privacy/evidence threshold %',coalesce(p_sample_size,0),v_threshold; end if;
  if p_measured_on is null then raise exception 'measurement date required'; end if;
  if nullif(trim(coalesce(p_methodology,'')),'') is null then raise exception 'methodology required'; end if;

  insert into public.mela_education_pilot_measurements(pilot_id,cohort_id,metric_key,measurement_period,measured_on,value,sample_size,methodology,evidence_note,data_quality,recorded_by)
  values(p_pilot_id,p_cohort_id,p_metric_key,p_measurement_period,p_measured_on,p_value,p_sample_size,trim(p_methodology),nullif(trim(coalesce(p_evidence_note,'')),''),p_data_quality,v_uid)
  on conflict(pilot_id,cohort_id,metric_key,measurement_period,measured_on) do update set
    value=excluded.value,sample_size=excluded.sample_size,methodology=excluded.methodology,
    evidence_note=excluded.evidence_note,data_quality=excluded.data_quality,recorded_by=excluded.recorded_by
  returning id into v_id;
  return v_id;
end;
$$;

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

  select * into v_base from public.mela_education_pilot_measurements
   where pilot_id=p_pilot_id and cohort_id=p_cohort_id and metric_key=p_metric_key
     and measurement_period='baseline' and data_quality='verified'
   order by measured_on asc,created_at asc limit 1;
  if not found then raise exception 'verified baseline measurement required'; end if;
  select * into v_end from public.mela_education_pilot_measurements
   where pilot_id=p_pilot_id and cohort_id=p_cohort_id and metric_key=p_metric_key
     and measurement_period in ('endline','followup') and data_quality='verified'
   order by measured_on desc,created_at desc limit 1;
  if not found then raise exception 'verified endline or follow-up measurement required'; end if;
  if least(v_base.sample_size,v_end.sample_size) < v_threshold then raise exception 'verified measurement sample is below the metric privacy threshold'; end if;

  insert into public.mela_impact_measurements(
    partner_organization_id,pilot_id,cohort_id,metric_key,stage_key,period_start,period_end,sample_size,
    baseline_value,end_value,methodology,evidence_note,source_reference,validation_status,measured_by,review_note
  ) values (
    v_pilot.partner_organization_id,p_pilot_id,p_cohort_id,p_metric_key,v_cohort.stage_key,
    v_base.measured_on,v_end.measured_on,least(v_base.sample_size,v_end.sample_size),v_base.value,v_end.value,
    concat('Pilot design: ',v_pilot.evaluation_design,'. Pilot methodology: ',coalesce(v_pilot.methodology_note,'—'),'. Baseline: ',v_base.methodology,'. Endline/follow-up: ',v_end.methodology),
    concat_ws(' | ',nullif(v_base.evidence_note,''),nullif(v_end.evidence_note,'')),
    'pilot:'||p_pilot_id::text,'reviewed',(select auth.uid()),
    'Generated from Founder/Admin-verified pilot baseline and endline/follow-up measurements; final interpretation still requires explicit review.'
  )
  on conflict do nothing
  returning id into v_id;

  if v_id is null then
    select id into v_id from public.mela_impact_measurements
     where pilot_id=p_pilot_id and cohort_id=p_cohort_id and metric_key=p_metric_key
     order by created_at desc limit 1;
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
  v_verified_base integer;
  v_verified_end integer;
begin
  if not private.is_admin_user() then raise exception 'admin access required'; end if;
  if p_decision not in ('supported','inconclusive','rejected') then raise exception 'decision must be supported, inconclusive or rejected'; end if;
  if nullif(trim(coalesce(p_review_note,'')),'') is null then raise exception 'review note is required'; end if;
  select * into v_row from public.mela_impact_measurements where id=p_measurement_id for update;
  if not found then raise exception 'impact summary not found'; end if;
  select privacy_threshold,title into v_threshold,v_metric_title from public.mela_outcome_metrics where metric_key=v_row.metric_key;
  if p_decision='supported' then
    if v_row.pilot_id is null or v_row.cohort_id is null then raise exception 'supported impact requires a linked Mela education pilot and cohort'; end if;
    if v_row.sample_size < coalesce(v_threshold,10) then raise exception 'sample size % is below threshold %',v_row.sample_size,coalesce(v_threshold,10); end if;
    if v_row.baseline_value is null or v_row.end_value is null then raise exception 'baseline and end values are required'; end if;
    select count(*) into v_verified_base from public.mela_education_pilot_measurements where pilot_id=v_row.pilot_id and cohort_id=v_row.cohort_id and metric_key=v_row.metric_key and measurement_period='baseline' and data_quality='verified';
    select count(*) into v_verified_end from public.mela_education_pilot_measurements where pilot_id=v_row.pilot_id and cohort_id=v_row.cohort_id and metric_key=v_row.metric_key and measurement_period in ('endline','followup') and data_quality='verified';
    if v_verified_base=0 or v_verified_end=0 then raise exception 'supported impact requires Founder/Admin-verified baseline and endline/follow-up pilot measurements'; end if;
  end if;
  update public.mela_impact_measurements set validation_status=p_decision,review_note=trim(p_review_note),reviewed_by=(select auth.uid()),reviewed_at=now(),updated_at=now() where id=p_measurement_id;
  return jsonb_build_object('id',p_measurement_id,'metric_key',v_row.metric_key,'metric_title',v_metric_title,'decision',p_decision,'sample_size',v_row.sample_size,'privacy_threshold',coalesce(v_threshold,10),'pilot_id',v_row.pilot_id,'cohort_id',v_row.cohort_id);
end;
$$;

-- Legacy direct summary recording stays available only for drafts/inconclusive/rejected evidence.
-- It can never be marked supported unless linked to verified pilot evidence through the review guard above.

create or replace function public.get_my_partner_education_impact()
returns jsonb
language plpgsql
stable
set search_path=''
as $$
declare v_uid uuid := (select auth.uid());
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  return jsonb_build_object(
    'pilots',public.get_my_education_pilots(),
    'reviewed_summaries',coalesce((select jsonb_agg(jsonb_build_object(
      'id',x.id,'partner_organization_id',x.partner_organization_id,'pilot_id',x.pilot_id,'cohort_id',x.cohort_id,
      'metric_key',x.metric_key,'metric_title',m.title,'stage_key',x.stage_key,'period_start',x.period_start,'period_end',x.period_end,
      'sample_size',x.sample_size,'baseline_value',x.baseline_value,'end_value',x.end_value,'change_value',x.change_value,
      'unit',m.unit,'direction',m.direction,'methodology',x.methodology,'evidence_note',x.evidence_note,'source_reference',x.source_reference,
      'validation_status',x.validation_status,'review_note',x.review_note,'reviewed_at',x.reviewed_at
    ) order by x.period_end desc,x.created_at desc)
    from public.mela_impact_measurements x join public.mela_outcome_metrics m on m.metric_key=x.metric_key
    where private.is_admin_user() or private.has_sector_partner_membership(x.partner_organization_id,v_uid,false)),'[]'::jsonb),
    'defined_metrics',coalesce((select jsonb_agg(jsonb_build_object('metric_key',m.metric_key,'title',m.title,'description',m.description,'unit',m.unit,'direction',m.direction,'target_value',m.target_value,'privacy_threshold',m.privacy_threshold) order by m.engine_key,m.metric_key) from public.mela_outcome_metrics m where m.active),'[]'::jsonb),
    'supported_summary_count',(select count(*) from public.mela_impact_measurements x where x.validation_status='supported' and (private.is_admin_user() or private.has_sector_partner_membership(x.partner_organization_id,v_uid,false))),
    'impact_claim',case when exists(select 1 from public.mela_impact_measurements x where x.validation_status='supported' and (private.is_admin_user() or private.has_sector_partner_membership(x.partner_organization_id,v_uid,false))) then 'Reviewed local pilot summaries include supported improvement. Claims must remain scoped to metric, cohort, period, sample size and evaluation design.' else 'No locally supported impact claim is available yet. Pilot architecture or provisional measurements do not count as proven impact.' end
  );
end;
$$;

create or replace function public.admin_education_value_readiness_v5()
returns jsonb
language plpgsql
stable
set search_path=''
as $$
declare
  v_base jsonb;
  v_checks jsonb;
  v_project_templates integer;
  v_approved_or_pilot_projects integer;
  v_reviewed_school_instructional_links integer;
  v_supported_impact integer;
  v_approved_alignment integer;
begin
  if not private.is_admin_user() then raise exception 'admin access required'; end if;
  v_base := public.admin_education_value_readiness_v3();
  select count(*) into v_project_templates from public.mela_local_challenge_templates where active;
  select count(*) into v_approved_or_pilot_projects from public.mela_local_challenge_templates where active and content_status in ('approved','pilot');
  select count(*) into v_reviewed_school_instructional_links from public.mela_curriculum_resource_links r join public.mela_curriculum_objectives o on o.id=r.objective_id where r.active and o.stage_key like 'school_%' and r.resource_type in ('lesson','practice_topic','practice_question','assessment','assessment_question','offline_pack');
  select count(*) into v_supported_impact from public.mela_impact_measurements where validation_status='supported';
  select count(*) into v_approved_alignment from public.mela_curriculum_alignments where active and review_status='approved';

  v_checks := (v_base->'checks') || jsonb_build_array(
    jsonb_build_object('key','ethiopian_project_frameworks','title','Ethiopian-context project framework','status',case when v_project_templates>=10 then 'foundation' else 'gap' end,'evidence',jsonb_build_object('framework_templates',v_project_templates,'approved_or_pilot',v_approved_or_pilot_projects),'required','stage-safe reviewed project set','why','Authentic local projects can turn learning into applied capability, but framework examples must be educator-reviewed before normal learner use.'),
    jsonb_build_object('key','reviewed_school_instructional_links','title','Reviewed school instructional content linked to objectives','status',case when v_reviewed_school_instructional_links>0 then 'foundation' else 'gap' end,'evidence',v_reviewed_school_instructional_links,'required','reviewed Grades 1–12 lessons/practice/assessments linked to objectives','why','Broad competencies and project frameworks are not enough; real school learning requires reviewed instructional content and assessment evidence.'),
    jsonb_build_object('key','qualified_curriculum_review','title','Qualified curriculum alignment review','status',case when v_approved_alignment>0 then 'pilot' else 'external_blocker' end,'evidence',v_approved_alignment,'required','approved mappings after qualified educator/curriculum review against authoritative sources','why','Mela must distinguish its internal bridge from verified Ethiopian curriculum alignment.'),
    jsonb_build_object('key','supported_local_impact','title','Reviewed supported local impact evidence','status',case when v_supported_impact>0 then 'pilot' else 'external_blocker' end,'evidence',v_supported_impact,'required','reviewed impact summary generated from verified pilot baseline and endline/follow-up evidence','why','Technical capability becomes demonstrated contribution only after reviewed local outcome evidence supports improvement.')
  );
  return jsonb_build_object(
    'generated_at',now(),'value_thesis',v_base->>'value_thesis','checks',v_checks,
    'summary',(v_base->'summary') || jsonb_build_object(
      'local_project_frameworks',v_project_templates,'approved_or_pilot_local_projects',v_approved_or_pilot_projects,
      'reviewed_school_instructional_links',v_reviewed_school_instructional_links,'approved_curriculum_alignments',v_approved_alignment,
      'supported_local_impact_measurements',v_supported_impact,
      'ready_or_foundation',(select count(*) from jsonb_array_elements(v_checks) x where x->>'status' in ('ready','foundation','pilot')),
      'gaps',(select count(*) from jsonb_array_elements(v_checks) x where x->>'status'='gap'),
      'external_blockers',(select count(*) from jsonb_array_elements(v_checks) x where x->>'status'='external_blocker'),
      'impact_claim_status',case when (select count(*) from jsonb_array_elements(v_checks) x where x->>'status' in ('gap','external_blocker'))=0 and v_supported_impact>0 then 'evidence_ready' else 'not_yet_proven' end
    )
  );
end;
$$;

create or replace function public.get_mela_education_value_status()
returns jsonb
language plpgsql
stable
set search_path=''
as $$
declare v_r jsonb; v_s jsonb;begin
 if not private.is_admin_user() then raise exception 'admin access required'; end if;
 v_r:=public.admin_education_value_readiness_v5(); v_s:=v_r->'summary';
 return jsonb_build_object(
  'claim_state',coalesce(v_s->>'impact_claim_status','not_yet_proven'),
  'impact_claim',case when coalesce((v_s->>'supported_local_impact_measurements')::int,0)>0 then 'Reviewed local pilot evidence includes supported improvement; claims must remain scoped to the measured cohort, metric, period, sample size and evaluation design.' else 'Mela has education-value architecture but no locally supported impact evidence yet. Do not market educational impact as proven.' end,
  'readiness',v_r,
  'guardrails',jsonb_build_object('real_pilot_protocol_required',true,'founder_admin_verification_required_for_verified_measurements',true,'human_curriculum_review_required',true,'privacy_thresholds_enforced',true,'no_supported_claim_without_verified_baseline_and_endline',true)
 );
end;
$$;

update public.mela_education_engines set current_assets=current_assets || jsonb_build_object(
 'pilot_protocol_tables',jsonb_build_array('mela_education_pilots','mela_education_pilot_cohorts','mela_education_pilot_metrics','mela_education_pilot_measurements'),
 'reviewed_impact_summaries','mela_impact_measurements','readiness_rpc','admin_education_value_readiness_v5'
),updated_at=now() where engine_key='institution_outcomes';

revoke all on function public.admin_build_pilot_impact_summary(uuid,uuid,text) from public,anon;
grant execute on function public.admin_build_pilot_impact_summary(uuid,uuid,text) to authenticated,service_role;
revoke all on function public.admin_education_value_readiness_v5() from public,anon;
grant execute on function public.admin_education_value_readiness_v5() to authenticated,service_role;
revoke all on function public.get_mela_education_value_status() from public,anon;
grant execute on function public.get_mela_education_value_status() to authenticated,service_role;
;
