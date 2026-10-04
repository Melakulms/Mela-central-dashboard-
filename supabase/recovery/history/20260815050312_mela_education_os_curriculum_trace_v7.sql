-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815050312
create or replace function public.get_my_education_os_v2()
returns jsonb
language plpgsql
stable
set search_path=''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_stage text;
  v_grade smallint;
  v_home jsonb;
  v_approved_count integer;
  v_official_subject_count integer;
  v_objective_count integer;
  v_resource_link_count integer;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select education_stage_key,grade_level into v_stage,v_grade from public.profiles where id=v_uid;
  v_home := public.get_my_learning_home_v3();
  if v_stage is null then
    return jsonb_build_object('version','2026.08-education-os-v7','home',v_home,'curriculum_bridge','[]'::jsonb,'official_subjects','[]'::jsonb,'curriculum_objectives','[]'::jsonb,'local_challenges','[]'::jsonb,'value_loop',jsonb_build_array('onboard','diagnose','learn','practice','master','build','prove','plan','progress','measure'),'impact_truth','Mela does not claim educational impact for a learner or institution until real local evidence has been measured and reviewed.');
  end if;
  select count(*) into v_approved_count from public.mela_curriculum_alignments a where a.stage_key=v_stage and a.active and a.review_status='approved';
  select count(*) into v_official_subject_count from public.mela_national_subject_catalog n where n.active and n.stage_key=v_stage;
  select count(*) into v_objective_count from public.mela_curriculum_objectives o where o.stage_key=v_stage and o.content_status='published' and (o.grade_level is null or v_grade is null or o.grade_level=v_grade);
  select count(*) into v_resource_link_count from public.mela_curriculum_resource_links r join public.mela_curriculum_objectives o on o.id=r.objective_id where r.active and o.stage_key=v_stage and o.content_status='published' and (o.grade_level is null or v_grade is null or o.grade_level=v_grade);
  return jsonb_build_object(
    'version','2026.08-education-os-v7',
    'home',v_home,
    'official_subjects',coalesce((select jsonb_agg(jsonb_build_object(
       'subject_key',n.subject_key,'subject_title',n.subject_title,'track_key',n.track_key,'optional',n.optional,
       'source_name',n.source_name,'source_url',n.source_url,'source_status',n.source_status
     ) order by n.display_order,n.subject_title) from public.mela_national_subject_catalog n where n.active and n.stage_key=v_stage),'[]'::jsonb),
    'curriculum_objectives',coalesce((select jsonb_agg(jsonb_build_object(
       'id',o.id,'objective_key',o.objective_key,'subject_key',o.subject_key,'subject_title',s.title,
       'title',o.title,'description',o.description,'cognitive_level',o.cognitive_level,'target_score',o.target_score,
       'official_alignment_status',o.official_alignment_status,'content_status',o.content_status,
       'competency_id',o.competency_id,'resource_link_count',(select count(*) from public.mela_curriculum_resource_links r where r.objective_id=o.id and r.active)
     ) order by o.display_order,o.objective_key) from public.mela_curriculum_objectives o left join public.mela_curriculum_subjects s on s.subject_key=o.subject_key where o.stage_key=v_stage and o.content_status='published' and (o.grade_level is null or v_grade is null or o.grade_level=v_grade)),'[]'::jsonb),
    'curriculum_bridge',coalesce((select jsonb_agg(jsonb_build_object(
      'competency_id',a.competency_id,'competency_key',c.competency_key,'competency_title',c.title,
      'subject_key',a.subject_key,'subject_title',a.subject_title,'strand_title',a.strand_title,
      'review_status',a.review_status,'alignment_note',a.alignment_note,'source_reference',a.source_reference,
      'local_contexts',a.local_contexts
    ) order by c.display_order) from public.mela_curriculum_alignments a join public.learning_competencies c on c.id=a.competency_id where a.stage_key=v_stage and a.active and a.review_status<>'retired'),'[]'::jsonb),
    'curriculum_status',jsonb_build_object(
      'official_subject_listings',v_official_subject_count,
      'published_objectives',v_objective_count,
      'linked_learning_resources',v_resource_link_count,
      'approved_competency_alignments',v_approved_count,
      'stage_alignment_count',(select count(*) from public.mela_curriculum_alignments a where a.stage_key=v_stage and a.active and a.review_status<>'retired'),
      'official_objective_alignment_count',(select count(*) from public.mela_curriculum_objectives o where o.stage_key=v_stage and o.content_status='published' and o.official_alignment_status not in ('not_officially_mapped','pending_review')),
      'claim',case when (select count(*) from public.mela_curriculum_objectives o where o.stage_key=v_stage and o.content_status='published' and o.official_alignment_status not in ('not_officially_mapped','pending_review'))>0 then 'Official subject structure is present and some objective mappings have passed the configured official-alignment workflow; inspect item status before making claims.' else 'Official Ethiopian subject listings are represented where available, but detailed Mela objective-to-official-curriculum mapping remains under qualified source/educator review.' end
    ),
    'local_challenges',coalesce((select jsonb_agg(jsonb_build_object(
      'challenge_key',x.challenge_key,'title',x.title,'description',x.description,'sector_key',x.sector_key,
      'competency_keys',x.competency_keys,'evidence_requirements',x.evidence_requirements,
      'offline_friendly',x.offline_friendly,'safeguarding_level',x.safeguarding_level,
      'content_status',x.content_status,'local_context_note',x.local_context_note,
      'learner_use',case when x.content_status='approved' then 'ready' when x.content_status='pilot' then 'supervised_pilot' else 'example_under_review' end
    ) order by case x.content_status when 'approved' then 1 when 'pilot' then 2 else 3 end,x.title) from public.mela_local_challenge_templates x where x.active and x.content_status<>'retired' and v_stage=any(x.stage_keys)),'[]'::jsonb),
    'benchmark_validation',coalesce((select jsonb_agg(jsonb_build_object(
      'country_code',a.country_code,'engine_key',a.engine_key,'product_surface',a.product_surface,
      'adaptation',a.mela_adaptation,'outcome_metric_key',a.outcome_metric_key,
      'local_validation_status',a.ethiopia_validation_status,'local_validation_note',a.ethiopia_validation_note
    ) order by a.priority desc,a.country_code) from public.education_benchmark_adaptations a where a.active and v_stage=any(a.target_stages)),'[]'::jsonb),
    'value_loop',jsonb_build_array(
      jsonb_build_object('step','diagnose','system','Mastery + evidence diagnostic'),
      jsonb_build_object('step','learn','system','Stage, subject and objective-linked learning'),
      jsonb_build_object('step','practice','system','Targeted practice and catch-up'),
      jsonb_build_object('step','master','system','Evidence-weighted Mastery Engine'),
      jsonb_build_object('step','build','system','Safeguarded Ethiopian-context projects'),
      jsonb_build_object('step','prove','system','Learner Passport and verified evidence'),
      jsonb_build_object('step','plan','system','Mela Next'),
      jsonb_build_object('step','progress','system','Opportunity Graph / education transition'),
      jsonb_build_object('step','measure','system','Privacy-protected outcome measurement')
    ),
    'impact_truth','Mela is technically designed to create and measure educational value, but local sector impact is not considered proven until Ethiopian pilots produce reviewed before/after evidence with adequate sample sizes.'
  );
end;
$$;
revoke all on function public.get_my_education_os_v2() from public,anon;
grant execute on function public.get_my_education_os_v2() to authenticated,service_role;
;
