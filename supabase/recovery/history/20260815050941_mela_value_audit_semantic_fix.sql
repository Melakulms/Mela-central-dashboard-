-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815050941
create or replace function public.admin_education_value_readiness_v4()
returns jsonb
language plpgsql
stable
set search_path to ''
as $$
declare
  v_base jsonb;
  v_checks jsonb;
  v_project_templates integer;
  v_project_links integer;
  v_reviewed_school_instructional_links integer;
  v_supported_impact integer;
  v_reviewed_alignment integer;
  v_approved_alignment integer;
begin
  if not private.is_admin_user() then raise exception 'admin access required'; end if;
  v_base := public.admin_education_value_readiness_v3();
  select count(*) into v_project_templates from public.mela_local_challenge_templates where active;
  select count(*) into v_project_links from public.mela_curriculum_resource_links where active and resource_type='project_template';
  select count(*) into v_reviewed_school_instructional_links
  from public.mela_curriculum_resource_links r
  join public.mela_curriculum_objectives o on o.id=r.objective_id
  where r.active and o.stage_key like 'school_%'
    and r.resource_type in ('lesson','practice_topic','practice_question','assessment','assessment_question','offline_pack');
  select count(*) into v_supported_impact from public.mela_impact_measurements where validation_status='supported';
  select count(*) into v_reviewed_alignment from public.mela_curriculum_alignments where active and review_status in ('educator_review','curriculum_review','approved');
  select count(*) into v_approved_alignment from public.mela_curriculum_alignments where active and review_status='approved';

  select coalesce(jsonb_agg(x),'[]'::jsonb) into v_checks
  from jsonb_array_elements(v_base->'checks') x
  where x->>'key' <> 'school_content_objective_links';

  v_checks := v_checks || jsonb_build_array(
    jsonb_build_object('key','ethiopian_project_frameworks','title','Ethiopian-context project framework','status',case when v_project_templates>=10 and v_project_links>0 then 'foundation' else 'gap' end,'evidence',jsonb_build_object('templates',v_project_templates,'objective_links',v_project_links),'required','reviewed stage-safe project framework','why','Authentic Ethiopian-context projects can turn subject learning into applied capability, while remaining clearly separate from official curriculum claims.'),
    jsonb_build_object('key','reviewed_school_instructional_links','title','Reviewed school instructional content linked to objectives','status',case when v_reviewed_school_instructional_links>0 then 'foundation' else 'gap' end,'evidence',v_reviewed_school_instructional_links,'required','reviewed Grades 1–12 lessons/practice/assessments linked to objectives','why','Broad competencies and project frameworks are not enough; real school learning requires reviewed instructional content and assessment evidence.'),
    jsonb_build_object('key','qualified_curriculum_review','title','Qualified curriculum alignment review','status',case when v_approved_alignment>0 then 'pilot' when v_reviewed_alignment>0 then 'foundation' else 'external_blocker' end,'evidence',jsonb_build_object('in_review_or_approved',v_reviewed_alignment,'approved',v_approved_alignment),'required','qualified educator/curriculum review against authoritative sources','why','Mela must distinguish an internal framework bridge from approved Ethiopian curriculum alignment.'),
    jsonb_build_object('key','supported_local_impact','title','Reviewed supported local impact evidence','status',case when v_supported_impact>0 then 'pilot' else 'external_blocker' end,'evidence',v_supported_impact,'required','reviewed supported baseline-to-endline education impact measurement','why','A technically capable platform becomes a proven education-sector contributor only after reviewed local outcome evidence supports improvement.')
  );

  return jsonb_build_object(
    'generated_at',now(),
    'value_thesis',v_base->>'value_thesis',
    'checks',v_checks,
    'summary',(v_base->'summary') || jsonb_build_object(
      'local_project_frameworks',v_project_templates,
      'project_objective_links',v_project_links,
      'school_content_objective_links',v_reviewed_school_instructional_links,
      'reviewed_school_instructional_links',v_reviewed_school_instructional_links,
      'reviewed_or_approved_curriculum_alignments',v_reviewed_alignment,
      'approved_curriculum_alignments',v_approved_alignment,
      'supported_local_impact_measurements',v_supported_impact,
      'ready_or_foundation',(select count(*) from jsonb_array_elements(v_checks) x where x->>'status' in ('ready','foundation','pilot')),
      'gaps',(select count(*) from jsonb_array_elements(v_checks) x where x->>'status'='gap'),
      'external_blockers',(select count(*) from jsonb_array_elements(v_checks) x where x->>'status'='external_blocker'),
      'impact_claim_status',case when (select count(*) from jsonb_array_elements(v_checks) x where x->>'status' in ('gap','external_blocker'))=0 and v_supported_impact>0 then 'evidence_ready' else 'not_yet_proven' end
    )
  );
end;
$$;
;
