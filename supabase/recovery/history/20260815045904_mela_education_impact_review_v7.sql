-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815045904
alter table public.mela_impact_measurements add column if not exists review_note text;

create or replace function public.admin_record_education_impact(
  p_partner_organization_id uuid,
  p_metric_key text,
  p_stage_key text,
  p_period_start date,
  p_period_end date,
  p_sample_size integer,
  p_baseline_value numeric,
  p_end_value numeric,
  p_methodology text,
  p_evidence_note text,
  p_source_reference text
)
returns uuid
language plpgsql
set search_path=''
as $$
declare v_id uuid; v_type text;
begin
  if not private.is_admin_user() then raise exception 'admin access required'; end if;
  if p_sample_size is null or p_sample_size < 1 then raise exception 'sample size must be at least 1'; end if;
  if p_period_start is null or p_period_end is null or p_period_end < p_period_start then raise exception 'invalid measurement period'; end if;
  if nullif(trim(coalesce(p_methodology,'')),'') is null then raise exception 'methodology is required'; end if;
  select partner_type_key into v_type from public.sector_partner_organizations where id=p_partner_organization_id;
  if v_type is null or v_type not in ('school','college_tvet','university') then raise exception 'education partner organization required'; end if;
  if not exists(select 1 from public.mela_outcome_metrics where metric_key=p_metric_key and active) then raise exception 'active outcome metric required'; end if;
  if p_stage_key is not null and not exists(select 1 from public.education_audience_stages where stage_key=p_stage_key) then raise exception 'invalid education stage'; end if;
  insert into public.mela_impact_measurements(partner_organization_id,metric_key,stage_key,period_start,period_end,sample_size,baseline_value,end_value,methodology,evidence_note,source_reference,validation_status,measured_by)
  values(p_partner_organization_id,p_metric_key,p_stage_key,p_period_start,p_period_end,p_sample_size,p_baseline_value,p_end_value,trim(p_methodology),nullif(trim(coalesce(p_evidence_note,'')),''),nullif(trim(coalesce(p_source_reference,'')),''),'draft',(select auth.uid()))
  returning id into v_id;
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
declare v_row public.mela_impact_measurements%rowtype; v_threshold integer; v_metric_title text;
begin
  if not private.is_admin_user() then raise exception 'admin access required'; end if;
  if p_decision not in ('supported','inconclusive','rejected') then raise exception 'decision must be supported, inconclusive or rejected'; end if;
  if nullif(trim(coalesce(p_review_note,'')),'') is null then raise exception 'review note is required'; end if;
  select * into v_row from public.mela_impact_measurements where id=p_measurement_id for update;
  if not found then raise exception 'impact measurement not found'; end if;
  select privacy_threshold,title into v_threshold,v_metric_title from public.mela_outcome_metrics where metric_key=v_row.metric_key;
  if p_decision='supported' and v_row.sample_size < coalesce(v_threshold,10) then
    raise exception 'sample size % is below the privacy/evidence threshold % for this metric',v_row.sample_size,coalesce(v_threshold,10);
  end if;
  if p_decision='supported' and (v_row.baseline_value is null or v_row.end_value is null) then
    raise exception 'baseline and end values are required before marking an impact measurement supported';
  end if;
  update public.mela_impact_measurements set
    validation_status=p_decision,
    review_note=trim(p_review_note),
    reviewed_by=(select auth.uid()),
    reviewed_at=now(),
    updated_at=now()
  where id=p_measurement_id;
  return jsonb_build_object('id',p_measurement_id,'metric_key',v_row.metric_key,'metric_title',v_metric_title,'decision',p_decision,'sample_size',v_row.sample_size,'privacy_threshold',coalesce(v_threshold,10));
end;
$$;

create or replace function public.get_mela_education_blueprint()
returns jsonb
language sql
stable
set search_path=''
as $$
select jsonb_build_object(
  'version','2026.08-education-os-v7',
  'benchmark_country_count',(select count(*) from public.education_benchmark_systems where active),
  'source_practice_count',(select count(*) from public.education_benchmark_practices where active),
  'adaptation_count',(select count(*) from public.education_benchmark_adaptations where active),
  'curriculum_bridge_count',(select count(*) from public.mela_curriculum_alignments where active),
  'approved_curriculum_mapping_count',(select count(*) from public.mela_curriculum_alignments where active and review_status='approved'),
  'local_challenge_count',(select count(*) from public.mela_local_challenge_templates where active),
  'reviewed_impact_measurement_count',(select count(*) from public.mela_impact_measurements where validation_status in ('supported','inconclusive','rejected')),
  'stages',coalesce((select jsonb_agg(to_jsonb(s) order by s.display_order) from public.education_audience_stages s),'[]'::jsonb),
  'languages',coalesce((select jsonb_agg(jsonb_build_object('code',l.language_code,'name',l.language_name,'native_name',l.native_name,'enabled',l.enabled) order by l.sort_order) from public.platform_languages l where l.enabled),'[]'::jsonb),
  'engines',coalesce((select jsonb_agg(to_jsonb(e) order by e.display_order) from public.mela_education_engines e),'[]'::jsonb),
  'benchmarks',coalesce((select jsonb_agg(to_jsonb(b) order by b.country_name) from public.education_benchmark_systems b where b.active),'[]'::jsonb),
  'source_practices',coalesce((select jsonb_agg(to_jsonb(p) order by p.priority desc,p.country_code) from public.education_benchmark_practices p where p.active),'[]'::jsonb),
  'mela_adaptations',coalesce((select jsonb_agg(jsonb_build_object(
      'id',a.id,'country_code',a.country_code,'country_name',b.country_name,'engine_key',a.engine_key,
      'practice_key',a.practice_key,'source_practice_key',a.source_practice_key,'source_practice',a.source_practice,
      'mela_adaptation',a.mela_adaptation,'target_stages',a.target_stages,'product_surface',a.product_surface,
      'success_metric',a.success_metric,'outcome_metric_key',a.outcome_metric_key,'priority',a.priority,
      'implementation_status',a.implementation_status,'ethiopia_validation_status',a.ethiopia_validation_status,
      'ethiopia_validation_note',a.ethiopia_validation_note,'ethiopia_validated_at',a.ethiopia_validated_at,'active',a.active
    ) order by a.priority desc,b.country_name)
    from public.education_benchmark_adaptations a join public.education_benchmark_systems b on b.country_code=a.country_code where a.active),'[]'::jsonb),
  'curriculum_bridge',coalesce((select jsonb_agg(jsonb_build_object('competency_id',a.competency_id,'stage_key',a.stage_key,'subject_key',a.subject_key,'subject_title',a.subject_title,'strand_title',a.strand_title,'review_status',a.review_status,'alignment_note',a.alignment_note,'source_reference',a.source_reference) order by a.stage_key,a.subject_title) from public.mela_curriculum_alignments a where a.active and a.review_status<>'retired'),'[]'::jsonb),
  'local_challenges',coalesce((select jsonb_agg(to_jsonb(c) order by c.content_status,c.challenge_key) from public.mela_local_challenge_templates c where c.active and c.content_status<>'retired'),'[]'::jsonb),
  'outcome_metrics',coalesce((select jsonb_agg(to_jsonb(m) order by m.engine_key,m.metric_key) from public.mela_outcome_metrics m where m.active),'[]'::jsonb),
  'impact_truth','Benchmark adoption and technical implementation are not treated as proof of Ethiopian sector impact. Local claims require reviewed measurements with documented methods and adequate privacy-protected sample sizes.'
);
$$;

revoke all on function public.admin_record_education_impact(uuid,text,text,date,date,integer,numeric,numeric,text,text,text) from public,anon;
grant execute on function public.admin_record_education_impact(uuid,text,text,date,date,integer,numeric,numeric,text,text,text) to authenticated,service_role;
revoke all on function public.admin_review_education_impact(uuid,text,text) from public,anon;
grant execute on function public.admin_review_education_impact(uuid,text,text) to authenticated,service_role;
revoke all on function public.get_mela_education_blueprint() from public,anon;
grant execute on function public.get_mela_education_blueprint() to authenticated,service_role;
;
