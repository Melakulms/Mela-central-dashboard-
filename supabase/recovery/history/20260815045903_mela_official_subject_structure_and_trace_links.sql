-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815045903
create table if not exists public.mela_national_subject_catalog (
  id uuid primary key default gen_random_uuid(),
  jurisdiction text not null default 'Ethiopia',
  stage_key text not null references public.education_audience_stages(stage_key) on delete cascade,
  track_key text not null default 'common',
  subject_key text not null,
  subject_title text not null,
  optional boolean not null default false,
  source_name text not null,
  source_url text not null,
  source_status text not null default 'official_listing' check (source_status in ('official_listing','pending_review','retired')),
  verified_at timestamptz not null default now(),
  display_order smallint not null default 100,
  active boolean not null default true,
  unique(stage_key,track_key,subject_key)
);
create index if not exists mela_national_subject_catalog_stage_idx on public.mela_national_subject_catalog(stage_key,track_key,display_order) where active;
alter table public.mela_national_subject_catalog enable row level security;
revoke all on public.mela_national_subject_catalog from anon, authenticated;
grant select on public.mela_national_subject_catalog to authenticated;
create policy mela_national_subject_catalog_read on public.mela_national_subject_catalog for select to authenticated using (active);

insert into public.mela_national_subject_catalog(stage_key,track_key,subject_key,subject_title,optional,source_name,source_url,display_order)
values
('school_1_6','common','native_language','Native Language',false,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',10),
('school_1_6','common','federal_working_language','Federal Working Language',false,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',20),
('school_1_6','common','english','English Language',false,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',30),
('school_1_6','common','environmental_science','Environmental Science',false,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',40),
('school_1_6','common','mathematics','Mathematics',false,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',50),
('school_1_6','common','moral_education','Moral Education',false,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',60),
('school_1_6','common','art','Art',false,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',70),
('school_1_6','common','health_physical_education','Health & Physical Education',false,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',80),

('school_7_8','common','native_language','Native Language',false,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',10),
('school_7_8','common','federal_working_language','Federal Working Language',false,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',20),
('school_7_8','common','english','English Language',false,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',30),
('school_7_8','common','general_science','General Science',false,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',40),
('school_7_8','common','social_science','Social Science',false,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',50),
('school_7_8','common','civics','Civics Education',false,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',60),
('school_7_8','common','information_technology','Information Technology',false,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',70),
('school_7_8','common','health_physical_education','Health & Physical Education',false,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',80),
('school_7_8','common','employment_technical_education','Employment & Technical Education',false,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',90),
('school_7_8','common','mathematics','Mathematics',false,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',100),
('school_7_8','common','art','Art',false,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',110),

('school_9_10','common','english','English',false,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',10),
('school_9_10','common','mathematics','Mathematics',false,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',20),
('school_9_10','common','information_technology','Information Technology',false,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',30),
('school_9_10','common','physics','Physics',false,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',40),
('school_9_10','common','chemistry','Chemistry',false,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',50),
('school_9_10','common','biology','Biology',false,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',60),
('school_9_10','common','geography','Geography',false,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',70),
('school_9_10','common','history','History',false,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',80),
('school_9_10','common','civics','Civics Education',false,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',90),
('school_9_10','common','economics','Economics',false,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',100),
('school_9_10','common','native_language','Native Language',false,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',110),
('school_9_10','common','health_physical_education','Health & Physical Education',false,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',120),
('school_9_10','common','federal_working_language','Federal Working Language',true,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',130),
('school_9_10','common','foreign_language','Foreign Language',true,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',140),
('school_9_10','common','art','Art',true,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',150),

('school_11_12','natural_sciences','english','English',false,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',10),
('school_11_12','natural_sciences','mathematics','Mathematics',false,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',20),
('school_11_12','natural_sciences','physics','Physics',false,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',30),
('school_11_12','natural_sciences','chemistry','Chemistry',false,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',40),
('school_11_12','natural_sciences','biology','Biology',false,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',50),
('school_11_12','natural_sciences','information_technology','Information Technology',false,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',60),
('school_11_12','natural_sciences','agriculture','Agriculture',false,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',70),
('school_11_12','social_sciences','english','English',false,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',10),
('school_11_12','social_sciences','mathematics','Mathematics',false,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',20),
('school_11_12','social_sciences','geography','Geography',false,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',30),
('school_11_12','social_sciences','history','History',false,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',40),
('school_11_12','social_sciences','economics','Economics',false,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',50),
('school_11_12','social_sciences','information_technology','Information Technology',false,'FDRE Ministry of Education fact sheet','https://moe.gov.et/en/fact-sheets',60)
on conflict(stage_key,track_key,subject_key) do update set subject_title=excluded.subject_title,optional=excluded.optional,source_name=excluded.source_name,source_url=excluded.source_url,source_status='official_listing',verified_at=now(),display_order=excluded.display_order,active=true;

-- Broad, defensible content-to-objective links for existing post-secondary career pathways.
insert into public.mela_curriculum_resource_links(objective_id,resource_type,resource_id,resource_key,evidence_weight,required,active)
select o.id,'career_path',cp.id,cp.title,1,false,true
from public.career_paths cp
join public.mela_curriculum_objectives o on o.objective_key in ('core:tvet_technical','core:uni_domain')
on conflict do nothing;

insert into public.mela_curriculum_resource_links(objective_id,resource_type,resource_id,resource_key,evidence_weight,required,active)
select o.id,'career_path',cp.id,cp.title,1,false,true
from public.career_paths cp
join public.mela_curriculum_objectives o on (
 (cp.title='Software, Data & AI' and o.objective_key in ('core:tvet_digital','core:uni_digital'))
 or (cp.title='Technical Trades & Maintenance' and o.objective_key in ('core:tvet_safety','core:tvet_problem'))
 or (cp.title='Digital Media & Creative Production' and o.objective_key='core:uni_projects')
 or (cp.title='Education & Community Development' and o.objective_key in ('core:uni_academic','core:uni_professional'))
 or (cp.title='Health & Clinical Support' and o.objective_key in ('core:uni_professional','core:tvet_safety'))
)
on conflict do nothing;

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
      'alignment_note','Official Ethiopian subject structure is sourced from the FDRE Ministry of Education fact sheet. Detailed objective/standard alignment remains pending authoritative source mapping and educator review.'
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
    'active_interventions',coalesce((select jsonb_agg(jsonb_build_object(
      'id',i.id,'intervention_type',i.intervention_type,'status',i.status,'rationale',i.rationale,
      'baseline_score',i.baseline_score,'target_score',i.target_score,'recommended_at',i.recommended_at,
      'competency_id',i.competency_id,'objective_id',i.objective_id
    ) order by i.recommended_at desc) from public.mela_learning_interventions i where i.user_id=v_uid and i.status in ('recommended','accepted','in_progress')),'[]'::jsonb)
  );
end;
$$;

create or replace function public.get_mela_education_blueprint()
returns jsonb
language sql
stable
set search_path to ''
as $$
select jsonb_build_object(
  'version','2026.08-education-os-v3',
  'benchmark_country_count',(select count(*) from public.education_benchmark_systems where active),
  'source_practice_count',(select count(*) from public.education_benchmark_practices where active),
  'adaptation_count',(select count(*) from public.education_benchmark_adaptations where active),
  'stages',coalesce((select jsonb_agg(to_jsonb(s) order by s.display_order) from public.education_audience_stages s),'[]'::jsonb),
  'languages',coalesce((select jsonb_agg(jsonb_build_object('code',l.language_code,'name',l.language_name,'native_name',l.native_name,'enabled',l.enabled) order by l.sort_order) from public.platform_languages l where l.enabled),'[]'::jsonb),
  'curriculum',jsonb_build_object(
    'mela_core_objectives',(select count(*) from public.mela_curriculum_objectives where content_status='published'),
    'official_subject_listings',(select count(*) from public.mela_national_subject_catalog where active),
    'resource_links',(select count(*) from public.mela_curriculum_resource_links where active),
    'official_alignment_status',(select alignment_status from public.mela_curriculum_frameworks where framework_key='ethiopia_national_alignment'),
    'official_subject_source','FDRE Ministry of Education fact sheet'
  ),
  'engines',coalesce((select jsonb_agg(to_jsonb(e) order by e.display_order) from public.mela_education_engines e),'[]'::jsonb),
  'benchmarks',coalesce((select jsonb_agg(to_jsonb(b) order by b.country_name) from public.education_benchmark_systems b where b.active),'[]'::jsonb),
  'source_practices',coalesce((select jsonb_agg(to_jsonb(p) order by p.priority,p.country_code) from public.education_benchmark_practices p where p.active),'[]'::jsonb),
  'mela_adaptations',coalesce((select jsonb_agg(jsonb_build_object(
    'id',a.id,'country_code',a.country_code,'country_name',b.country_name,'engine_key',a.engine_key,'practice_key',a.practice_key,
    'source_practice_key',a.source_practice_key,'source_practice',a.source_practice,'mela_adaptation',a.mela_adaptation,
    'target_stages',a.target_stages,'product_surface',a.product_surface,'success_metric',a.success_metric,
    'outcome_metric_key',a.outcome_metric_key,'priority',a.priority,'implementation_status',a.implementation_status,'active',a.active
  ) order by a.priority desc,b.country_name) from public.education_benchmark_adaptations a join public.education_benchmark_systems b on b.country_code=a.country_code where a.active),'[]'::jsonb),
  'outcome_metrics',coalesce((select jsonb_agg(to_jsonb(m) order by m.engine_key,m.metric_key) from public.mela_outcome_metrics m where m.active),'[]'::jsonb)
);
$$;

create or replace function public.admin_education_value_readiness_v2()
returns jsonb
language plpgsql
stable
set search_path to ''
as $$
declare
  v_base jsonb;
  v_checks jsonb;
  v_official_subjects integer;
  v_school_links integer;
  v_all_links integer;
  v_real_verified_passport integer;
begin
  if not private.is_admin_user() then raise exception 'admin access required'; end if;
  v_base := public.admin_education_value_readiness();
  select count(*) into v_official_subjects from public.mela_national_subject_catalog where active;
  select count(*) into v_all_links from public.mela_curriculum_resource_links where active;
  select count(*) into v_school_links from public.mela_curriculum_resource_links r join public.mela_curriculum_objectives o on o.id=r.objective_id where r.active and o.stage_key like 'school_%';
  select count(*) into v_real_verified_passport from public.verified_skills v join public.profiles p on p.id=v.user_id where v.verified and lower(coalesce(p.email,'')) not like '%@mela.invalid';
  v_checks := (v_base->'checks') || jsonb_build_array(
    jsonb_build_object('key','official_subject_structure','title','Official Ethiopian subject structure','status',case when v_official_subjects>=40 then 'foundation' else 'gap' end,'evidence',v_official_subjects,'required','official Grades 1–12 subject listings','why','The learner architecture should reflect the subjects Ethiopia actually teaches before detailed standard mapping is completed.'),
    jsonb_build_object('key','school_content_objective_links','title','School content linked to learning objectives','status',case when v_school_links>0 then 'foundation' else 'gap' end,'evidence',v_school_links,'required','reviewed school lesson/practice/assessment links','why','Grades 1–12 impact requires real subject content tied to objectives, not only broad competency labels.'),
    jsonb_build_object('key','real_verified_passport_evidence','title','Real learner verified evidence','status',case when v_real_verified_passport>0 then 'pilot' else 'external_blocker' end,'evidence',v_real_verified_passport,'required','verified evidence from real pilot learners','why','Portable evidence must be validated on real learners before it supports impact claims.')
  );
  return jsonb_build_object(
    'generated_at',now(),
    'value_thesis',v_base->>'value_thesis',
    'checks',v_checks,
    'summary',(v_base->'summary') || jsonb_build_object(
      'official_subject_listings',v_official_subjects,
      'content_objective_links',v_all_links,
      'school_content_objective_links',v_school_links,
      'real_verified_passport_evidence',v_real_verified_passport,
      'ready_or_foundation',(select count(*) from jsonb_array_elements(v_checks) x where x->>'status' in ('ready','foundation','pilot')),
      'gaps',(select count(*) from jsonb_array_elements(v_checks) x where x->>'status'='gap'),
      'external_blockers',(select count(*) from jsonb_array_elements(v_checks) x where x->>'status'='external_blocker')
    )
  );
end;
$$;

revoke all on function public.admin_education_value_readiness_v2() from public;
grant execute on function public.admin_education_value_readiness_v2() to authenticated;

;
