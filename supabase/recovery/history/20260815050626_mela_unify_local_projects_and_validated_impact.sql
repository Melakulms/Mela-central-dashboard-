-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815050626
-- Connect existing Ethiopian-context challenge frameworks to Mela objectives without presenting them as reviewed curriculum content.
insert into public.mela_curriculum_resource_links(
  objective_id,resource_type,resource_id,resource_key,evidence_weight,required,active
)
select distinct
  o.id,'project_template',null::uuid,c.challenge_key,1.5,false,true
from public.mela_local_challenge_templates c
cross join lateral unnest(c.competency_keys) ck(competency_key)
join public.learning_competencies lc on lc.competency_key=ck.competency_key
join public.mela_curriculum_objectives o on o.competency_id=lc.id and o.content_status='published'
where c.active
  and not exists (
    select 1 from public.mela_curriculum_resource_links r
    where r.objective_id=o.id and r.resource_type='project_template' and r.resource_key=c.challenge_key and r.active
  );

create or replace function public.get_my_curriculum_map()
returns jsonb
language plpgsql
stable
set search_path to ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_profile public.profiles%rowtype;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select * into v_profile from public.profiles where id=v_uid;
  if not found then raise exception 'profile not found'; end if;

  return jsonb_build_object(
    'framework',jsonb_build_object(
      'framework_key','mela_core_v1',
      'title','Mela Core Learning Framework',
      'official_ethiopian_alignment_status',(select alignment_status from public.mela_curriculum_frameworks where framework_key='ethiopia_national_alignment'),
      'framework_alignment_count',(select count(*) from public.mela_curriculum_alignments a where a.active and a.stage_key=v_profile.education_stage_key),
      'verified_alignment_count',(select count(*) from public.mela_curriculum_alignments a where a.active and a.stage_key=v_profile.education_stage_key and a.review_status='verified'),
      'alignment_note','Official Ethiopian subject structure is sourced from the FDRE Ministry of Education fact sheet. Detailed competency/standard alignment remains a framework bridge until authoritative source mapping and qualified educator review are verified.'
    ),
    'stage_key',v_profile.education_stage_key,
    'grade_level',v_profile.grade_level,
    'official_subjects',coalesce((
      select jsonb_agg(jsonb_build_object(
        'track_key',s.track_key,'subject_key',s.subject_key,'title',s.subject_title,'optional',s.optional,
        'source_name',s.source_name,'source_url',s.source_url,'source_status',s.source_status
      ) order by s.track_key,s.display_order)
      from public.mela_national_subject_catalog s
      where s.active and s.stage_key=v_profile.education_stage_key
    ),'[]'::jsonb),
    'subjects',coalesce((
      select jsonb_agg(jsonb_build_object(
        'subject_key',s.subject_key,
        'title',s.title,
        'description',s.description,
        'objectives',coalesce((
          select jsonb_agg(jsonb_build_object(
            'id',o.id,'objective_key',o.objective_key,'title',o.title,'description',o.description,
            'objective_type',o.objective_type,'cognitive_level',o.cognitive_level,'target_score',o.target_score,
            'official_alignment_status',o.official_alignment_status,'competency_id',o.competency_id,
            'mastery_score',coalesce(m.mastery_score,0),'mastery_level',coalesce(m.mastery_level,'not_started'),
            'evidence_count',coalesce(m.evidence_count,0),'verified_evidence_count',coalesce(m.verified_evidence_count,0),
            'linked_resources',coalesce((select count(*) from public.mela_curriculum_resource_links r where r.objective_id=o.id and r.active),0)
          ) order by o.display_order,o.title)
          from public.mela_curriculum_objectives o
          left join public.learner_mastery_records m on m.competency_id=o.competency_id and m.user_id=v_uid
          where o.subject_key=s.subject_key and o.stage_key=v_profile.education_stage_key and o.content_status='published'
            and (o.grade_level is null or o.grade_level=v_profile.grade_level)
        ),'[]'::jsonb)
      ) order by s.display_order)
      from public.mela_curriculum_subjects s
      where s.active and v_profile.education_stage_key=any(s.stage_keys)
    ),'[]'::jsonb),
    'local_project_frameworks',coalesce((
      select jsonb_agg(jsonb_build_object(
        'challenge_key',c.challenge_key,'title',c.title,'description',c.description,'sector_key',c.sector_key,
        'competency_keys',c.competency_keys,'evidence_requirements',c.evidence_requirements,
        'local_context_note',c.local_context_note,'offline_friendly',c.offline_friendly,
        'safeguarding_level',c.safeguarding_level,'content_status',c.content_status,
        'review_note','Framework template only; educator/content review is required before use as approved instructional material.'
      ) order by c.title)
      from public.mela_local_challenge_templates c
      where c.active and v_profile.education_stage_key=any(c.stage_keys)
    ),'[]'::jsonb),
    'active_interventions',coalesce((select jsonb_agg(jsonb_build_object(
      'id',i.id,'intervention_type',i.intervention_type,'status',i.status,'rationale',i.rationale,
      'baseline_score',i.baseline_score,'target_score',i.target_score,'outcome_score',i.outcome_score,
      'recommended_at',i.recommended_at,'competency_id',i.competency_id,'objective_id',i.objective_id,
      'source_entity_type',i.source_entity_type,'source_entity_id',i.source_entity_id
    ) order by i.recommended_at desc) from public.mela_learning_interventions i where i.user_id=v_uid and i.status in ('recommended','accepted','in_progress')),'[]'::jsonb)
  );
end;
$$;

create or replace function public.get_my_learning_home_v4()
returns jsonb
language plpgsql
stable
set search_path to ''
as $$
declare
  v_base jsonb;
  v_curriculum jsonb;
begin
  v_base := public.get_my_learning_home_v3();
  v_curriculum := public.get_my_curriculum_map();
  return v_base || jsonb_build_object(
    'curriculum_map',v_curriculum,
    'value_loop',jsonb_build_object(
      'promise','Diagnose → Learn → Practice → Master → Build → Prove → Plan → Opportunity',
      'evidence_rule','Progress should be justified by evidence; content views alone do not count as mastery.',
      'official_curriculum_alignment',(v_curriculum->'framework'->>'official_ethiopian_alignment_status'),
      'verified_curriculum_alignment_count',coalesce((v_curriculum->'framework'->>'verified_alignment_count')::integer,0),
      'local_project_framework_count',jsonb_array_length(coalesce(v_curriculum->'local_project_frameworks','[]'::jsonb))
    )
  );
end;
$$;

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
  v_verified_alignment integer;
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
  select count(*) into v_reviewed_alignment from public.mela_curriculum_alignments where active and review_status in ('reviewed','verified');
  select count(*) into v_verified_alignment from public.mela_curriculum_alignments where active and review_status='verified';

  v_checks := (v_base->'checks') || jsonb_build_array(
    jsonb_build_object('key','ethiopian_project_frameworks','title','Ethiopian-context project framework','status',case when v_project_templates>=10 and v_project_links>0 then 'foundation' else 'gap' end,'evidence',jsonb_build_object('templates',v_project_templates,'objective_links',v_project_links),'required','reviewed stage-safe project framework','why','Authentic Ethiopian-context projects can turn subject learning into applied capability, while remaining clearly separate from official curriculum claims.'),
    jsonb_build_object('key','reviewed_school_instructional_links','title','Reviewed school instructional content linked to objectives','status',case when v_reviewed_school_instructional_links>0 then 'foundation' else 'gap' end,'evidence',v_reviewed_school_instructional_links,'required','reviewed Grades 1–12 lessons/practice/assessments linked to objectives','why','Broad competencies and project frameworks are not enough; real school learning requires reviewed instructional content and assessment evidence.'),
    jsonb_build_object('key','qualified_curriculum_review','title','Qualified curriculum alignment review','status',case when v_verified_alignment>0 then 'pilot' when v_reviewed_alignment>0 then 'foundation' else 'external_blocker' end,'evidence',jsonb_build_object('reviewed_or_verified',v_reviewed_alignment,'verified',v_verified_alignment),'required','qualified educator/curriculum review against authoritative sources','why','Mela must distinguish an internal framework bridge from verified Ethiopian curriculum alignment.'),
    jsonb_build_object('key','supported_local_impact','title','Reviewed supported local impact evidence','status',case when v_supported_impact>0 then 'pilot' else 'external_blocker' end,'evidence',v_supported_impact,'required','reviewed supported baseline-to-endline education impact measurement','why','A technically capable platform becomes a proven education-sector contributor only after reviewed local outcome evidence supports improvement.')
  );

  return jsonb_build_object(
    'generated_at',now(),
    'value_thesis',v_base->>'value_thesis',
    'checks',v_checks,
    'summary',(v_base->'summary') || jsonb_build_object(
      'local_project_frameworks',v_project_templates,
      'project_objective_links',v_project_links,
      'reviewed_school_instructional_links',v_reviewed_school_instructional_links,
      'reviewed_or_verified_curriculum_alignments',v_reviewed_alignment,
      'verified_curriculum_alignments',v_verified_alignment,
      'supported_local_impact_measurements',v_supported_impact,
      'ready_or_foundation',(select count(*) from jsonb_array_elements(v_checks) x where x->>'status' in ('ready','foundation','pilot')),
      'gaps',(select count(*) from jsonb_array_elements(v_checks) x where x->>'status'='gap'),
      'external_blockers',(select count(*) from jsonb_array_elements(v_checks) x where x->>'status'='external_blocker'),
      'impact_claim_status',case when (select count(*) from jsonb_array_elements(v_checks) x where x->>'status' in ('gap','external_blocker'))=0 and v_supported_impact>0 then 'evidence_ready' else 'not_yet_proven' end
    )
  );
end;
$$;

revoke all on function public.admin_education_value_readiness_v4() from public;
grant execute on function public.admin_education_value_readiness_v4() to authenticated;
;
