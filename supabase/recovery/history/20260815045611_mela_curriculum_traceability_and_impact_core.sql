-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815045611
-- Mela curriculum traceability and measurable impact core
create table if not exists public.mela_curriculum_frameworks (
  framework_key text primary key,
  title text not null,
  description text not null,
  framework_type text not null check (framework_type in ('mela_core','national_alignment','partner_extension')),
  jurisdiction text,
  version text not null,
  source_name text,
  source_url text,
  alignment_status text not null default 'internal' check (alignment_status in ('internal','pending_source_review','mapped','verified','retired')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.mela_curriculum_subjects (
  subject_key text primary key,
  title text not null,
  description text not null,
  category text not null,
  stage_keys text[] not null default '{}',
  min_grade smallint,
  max_grade smallint,
  active boolean not null default true,
  display_order smallint not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint mela_curriculum_subjects_grade_range check (
    (min_grade is null and max_grade is null) or
    (min_grade between 1 and 12 and max_grade between 1 and 12 and min_grade <= max_grade)
  )
);

create table if not exists public.mela_curriculum_objectives (
  id uuid primary key default gen_random_uuid(),
  objective_key text not null unique,
  framework_key text not null references public.mela_curriculum_frameworks(framework_key) on delete cascade,
  subject_key text not null references public.mela_curriculum_subjects(subject_key) on delete restrict,
  stage_key text not null references public.education_audience_stages(stage_key) on delete restrict,
  grade_level smallint,
  competency_id uuid references public.learning_competencies(id) on delete set null,
  title text not null,
  description text not null,
  objective_type text not null default 'mastery' check (objective_type in ('foundation','mastery','application','project','transition')),
  cognitive_level text not null default 'apply' check (cognitive_level in ('remember','understand','apply','analyze','evaluate','create')),
  target_score numeric not null default 80 check (target_score between 0 and 100),
  official_alignment_status text not null default 'not_officially_mapped' check (official_alignment_status in ('not_officially_mapped','pending_review','mapped','verified')),
  content_status text not null default 'draft' check (content_status in ('draft','review','published','retired')),
  display_order smallint not null default 100,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint mela_curriculum_objectives_grade_check check (grade_level is null or grade_level between 1 and 12)
);

create table if not exists public.mela_curriculum_resource_links (
  id uuid primary key default gen_random_uuid(),
  objective_id uuid not null references public.mela_curriculum_objectives(id) on delete cascade,
  resource_type text not null check (resource_type in ('career_path','module','lesson','practice_topic','practice_question','assessment','assessment_question','project_template','offline_pack','external_resource')),
  resource_id uuid,
  resource_key text,
  evidence_weight numeric not null default 1 check (evidence_weight > 0 and evidence_weight <= 5),
  required boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint mela_curriculum_resource_link_identity check (resource_id is not null or nullif(btrim(resource_key),'') is not null),
  unique (objective_id, resource_type, resource_id, resource_key)
);

create table if not exists public.mela_learning_interventions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  competency_id uuid references public.learning_competencies(id) on delete set null,
  objective_id uuid references public.mela_curriculum_objectives(id) on delete set null,
  intervention_type text not null check (intervention_type in ('catchup','practice','teacher_support','family_support','project','tutoring','transition_support')),
  source text not null default 'mela_system' check (source in ('mela_system','educator','guardian','learner','partner')),
  rationale text,
  baseline_score numeric check (baseline_score is null or baseline_score between 0 and 100),
  target_score numeric check (target_score is null or target_score between 0 and 100),
  outcome_score numeric check (outcome_score is null or outcome_score between 0 and 100),
  status text not null default 'recommended' check (status in ('recommended','accepted','in_progress','completed','cancelled')),
  recommended_at timestamptz not null default now(),
  started_at timestamptz,
  completed_at timestamptz,
  created_by uuid references public.profiles(id) on delete set null,
  evidence_note text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.institution_outcome_snapshots
  add column if not exists subject_breakdown jsonb not null default '{}'::jsonb,
  add column if not exists data_quality jsonb not null default '{}'::jsonb;

create index if not exists mela_curriculum_objectives_stage_grade_idx on public.mela_curriculum_objectives(stage_key, grade_level, subject_key, display_order);
create index if not exists mela_curriculum_objectives_competency_idx on public.mela_curriculum_objectives(competency_id);
create index if not exists mela_curriculum_resource_links_objective_idx on public.mela_curriculum_resource_links(objective_id, active);
create index if not exists mela_curriculum_resource_links_resource_idx on public.mela_curriculum_resource_links(resource_type, resource_id) where active;
create index if not exists mela_learning_interventions_user_status_idx on public.mela_learning_interventions(user_id, status, recommended_at desc);
create index if not exists mela_learning_interventions_competency_idx on public.mela_learning_interventions(competency_id);
create index if not exists mela_learning_interventions_objective_idx on public.mela_learning_interventions(objective_id);
create index if not exists mela_learning_interventions_created_by_idx on public.mela_learning_interventions(created_by);

alter table public.mela_curriculum_frameworks enable row level security;
alter table public.mela_curriculum_subjects enable row level security;
alter table public.mela_curriculum_objectives enable row level security;
alter table public.mela_curriculum_resource_links enable row level security;
alter table public.mela_learning_interventions enable row level security;

revoke all on public.mela_curriculum_frameworks from anon, authenticated;
revoke all on public.mela_curriculum_subjects from anon, authenticated;
revoke all on public.mela_curriculum_objectives from anon, authenticated;
revoke all on public.mela_curriculum_resource_links from anon, authenticated;
revoke all on public.mela_learning_interventions from anon, authenticated;

grant select on public.mela_curriculum_frameworks to authenticated;
grant select on public.mela_curriculum_subjects to authenticated;
grant select on public.mela_curriculum_objectives to authenticated;
grant select on public.mela_curriculum_resource_links to authenticated;
grant select, insert, update on public.mela_learning_interventions to authenticated;

create policy mela_curriculum_frameworks_read on public.mela_curriculum_frameworks for select to authenticated using (active);
create policy mela_curriculum_subjects_read on public.mela_curriculum_subjects for select to authenticated using (active);
create policy mela_curriculum_objectives_read on public.mela_curriculum_objectives for select to authenticated using (content_status <> 'retired');
create policy mela_curriculum_resource_links_read on public.mela_curriculum_resource_links for select to authenticated using (active);

create policy mela_learning_interventions_read on public.mela_learning_interventions for select to authenticated
using (
  (select auth.uid()) = user_id
  or private.can_educate_learner((select auth.uid()), user_id)
  or private.is_admin_user()
);

create policy mela_learning_interventions_insert on public.mela_learning_interventions for insert to authenticated
with check (
  ((select auth.uid()) = user_id and source = 'learner')
  or private.can_educate_learner((select auth.uid()), user_id)
  or private.is_admin_user()
);

create policy mela_learning_interventions_update on public.mela_learning_interventions for update to authenticated
using (
  (select auth.uid()) = user_id
  or private.can_educate_learner((select auth.uid()), user_id)
  or private.is_admin_user()
)
with check (
  (select auth.uid()) = user_id
  or private.can_educate_learner((select auth.uid()), user_id)
  or private.is_admin_user()
);

insert into public.mela_curriculum_frameworks(framework_key,title,description,framework_type,jurisdiction,version,source_name,alignment_status,active)
values
('mela_core_v1','Mela Core Learning Framework','Stage-appropriate Mela learning objectives that make mastery traceable from learning evidence to measurable outcomes. This is a Mela framework, not an official national curriculum.','mela_core','Ethiopia','1.0','Mela internal education design','internal',true),
('ethiopia_national_alignment','Ethiopian National Curriculum Alignment','Mapping layer reserved for verified alignment to official Ethiopian curriculum documents and approved subject/grade standards. No objective is treated as officially aligned until reviewed against authoritative source documents.','national_alignment','Ethiopia','pending','Official Ethiopian curriculum sources','pending_source_review',true)
on conflict (framework_key) do update set title=excluded.title,description=excluded.description,version=excluded.version,source_name=excluded.source_name,alignment_status=excluded.alignment_status,active=excluded.active,updated_at=now();

insert into public.mela_curriculum_subjects(subject_key,title,description,category,stage_keys,min_grade,max_grade,display_order)
values
('literacy_communication','Literacy & Communication','Reading, writing, speaking, listening, research and communication.','foundation',array['school_1_6','school_7_8','school_9_10','school_11_12','college_tvet','university'],1,12,10),
('mathematics_logic','Mathematics & Logic','Numeracy, mathematical reasoning, quantitative problem solving and logic.','foundation',array['school_1_6','school_7_8','school_9_10','school_11_12','college_tvet','university'],1,12,20),
('science_stem','Science & STEM','Scientific inquiry, STEM reasoning and evidence-based problem solving.','foundation',array['school_1_6','school_7_8','school_9_10','school_11_12','college_tvet','university'],1,12,30),
('digital_ai','Digital & AI','Digital literacy, coding, data, AI literacy and responsible technology use.','future_capability',array['school_1_6','school_7_8','school_9_10','school_11_12','college_tvet','university'],1,12,40),
('projects_problem_solving','Projects & Problem Solving','Applied projects, creativity, collaboration and authentic problem solving.','application',array['school_1_6','school_7_8','school_9_10','school_11_12','college_tvet','university'],1,12,50),
('life_transition','Life, Pathways & Transition','Learning habits, life skills, pathway navigation, professional readiness and transition.','transition',array['school_1_6','school_7_8','school_9_10','school_11_12','college_tvet','university'],1,12,60)
on conflict (subject_key) do update set title=excluded.title,description=excluded.description,category=excluded.category,stage_keys=excluded.stage_keys,min_grade=excluded.min_grade,max_grade=excluded.max_grade,active=true,display_order=excluded.display_order,updated_at=now();

-- Seed one traceable Mela Core objective for every currently active competency.
insert into public.mela_curriculum_objectives(
  objective_key,framework_key,subject_key,stage_key,grade_level,competency_id,title,description,objective_type,cognitive_level,target_score,official_alignment_status,content_status,display_order,metadata
)
select
  'core:'||c.competency_key,
  'mela_core_v1',
  case
    when c.domain_key in ('literacy','academic') then 'literacy_communication'
    when c.domain_key in ('numeracy') then 'mathematics_logic'
    when c.domain_key in ('science','stem') then 'science_stem'
    when c.domain_key in ('digital','ai') then 'digital_ai'
    when c.domain_key in ('projects','creativity','problem_solving','technical','safety') then 'projects_problem_solving'
    else 'life_transition'
  end,
  c.stage_key,
  null,
  c.id,
  c.title,
  c.description,
  case when c.domain_key in ('projects','creativity','problem_solving','technical') then 'application' when c.domain_key in ('transition','career','future','growth','professional','work_readiness','life') then 'transition' else 'mastery' end,
  case when c.domain_key in ('projects','creativity') then 'create' when c.domain_key in ('problem_solving','science','stem') then 'analyze' else 'apply' end,
  c.target_score,
  'not_officially_mapped',
  case when c.content_status='retired' then 'retired' else 'published' end,
  c.display_order,
  jsonb_build_object('source','learning_competencies','domain_key',c.domain_key,'domain_title',c.domain_title)
from public.learning_competencies c
on conflict (objective_key) do update set
  subject_key=excluded.subject_key,stage_key=excluded.stage_key,competency_id=excluded.competency_id,title=excluded.title,description=excluded.description,objective_type=excluded.objective_type,cognitive_level=excluded.cognitive_level,target_score=excluded.target_score,content_status=excluded.content_status,display_order=excluded.display_order,metadata=excluded.metadata,updated_at=now();

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
      'alignment_note','Mela Core objectives are product learning objectives. Official Ethiopian curriculum alignment remains pending authoritative source mapping and educator review.'
    ),
    'stage_key',v_profile.education_stage_key,
    'grade_level',v_profile.grade_level,
    'subjects',coalesce((
      select jsonb_agg(jsonb_build_object(
        'subject_key',s.subject_key,
        'title',s.title,
        'description',s.description,
        'objectives',coalesce((
          select jsonb_agg(jsonb_build_object(
            'id',o.id,
            'objective_key',o.objective_key,
            'title',o.title,
            'description',o.description,
            'objective_type',o.objective_type,
            'cognitive_level',o.cognitive_level,
            'target_score',o.target_score,
            'official_alignment_status',o.official_alignment_status,
            'competency_id',o.competency_id,
            'mastery_score',coalesce(m.mastery_score,0),
            'mastery_level',coalesce(m.mastery_level,'not_started'),
            'evidence_count',coalesce(m.evidence_count,0),
            'verified_evidence_count',coalesce(m.verified_evidence_count,0)
          ) order by o.display_order,o.title)
          from public.mela_curriculum_objectives o
          left join public.learner_mastery_records m on m.competency_id=o.competency_id and m.user_id=v_uid
          where o.subject_key=s.subject_key
            and o.stage_key=v_profile.education_stage_key
            and o.content_status='published'
            and (o.grade_level is null or o.grade_level=v_profile.grade_level)
        ),'[]'::jsonb)
      ) order by s.display_order)
      from public.mela_curriculum_subjects s
      where s.active and v_profile.education_stage_key=any(s.stage_keys)
    ),'[]'::jsonb),
    'active_interventions',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',i.id,'intervention_type',i.intervention_type,'status',i.status,'rationale',i.rationale,
        'baseline_score',i.baseline_score,'target_score',i.target_score,'recommended_at',i.recommended_at,
        'competency_id',i.competency_id,'objective_id',i.objective_id
      ) order by i.recommended_at desc)
      from public.mela_learning_interventions i
      where i.user_id=v_uid and i.status in ('recommended','accepted','in_progress')
    ),'[]'::jsonb)
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
      'official_curriculum_alignment',(v_curriculum->'framework'->>'official_ethiopian_alignment_status')
    )
  );
end;
$$;

create or replace function public.admin_education_value_readiness()
returns jsonb
language plpgsql
stable
set search_path to ''
as $$
declare
  v_real_learners integer;
  v_real_educators integer;
  v_verified_edu_partners integer;
  v_published_offline integer;
  v_objectives integer;
  v_trace_links integer;
  v_outcomes integer;
  v_langs integer;
  v_checks jsonb;
begin
  if not private.is_admin_user() then raise exception 'admin access required'; end if;

  select count(*) into v_real_learners from public.profiles where role='student'::public.user_role and lower(coalesce(email,'')) not like '%@mela.invalid';
  select count(*) into v_real_educators from public.educator_profiles ep join public.profiles p on p.id=ep.user_id where ep.verified and lower(coalesce(p.email,'')) not like '%@mela.invalid';
  select count(*) into v_verified_edu_partners from public.sector_partner_organizations where verification_status='verified' and partner_type_key in ('school','college_tvet','university');
  select count(*) into v_published_offline from public.mela_offline_content_packs where published;
  select count(*) into v_objectives from public.mela_curriculum_objectives where content_status='published';
  select count(*) into v_trace_links from public.mela_curriculum_resource_links where active;
  select count(*) into v_outcomes from public.mela_outcome_metrics where active;
  select count(*) into v_langs from public.platform_languages where enabled;

  v_checks := jsonb_build_array(
    jsonb_build_object('key','stage_architecture','title','Stage-specific learner architecture','status',case when (select count(*) from public.education_audience_stages)=6 then 'ready' else 'gap' end,'evidence',(select count(*) from public.education_audience_stages),'required',6,'why','Different age and education stages need different learning, safety and transition experiences.'),
    jsonb_build_object('key','curriculum_traceability','title','Curriculum/objective traceability','status',case when v_objectives>=36 then 'foundation' else 'gap' end,'evidence',v_objectives,'required',36,'why','Mastery must trace to explicit learning objectives rather than generic course completion.'),
    jsonb_build_object('key','official_ethiopia_alignment','title','Official Ethiopian curriculum mapping','status',case when (select alignment_status from public.mela_curriculum_frameworks where framework_key='ethiopia_national_alignment')='verified' then 'ready' else 'external_blocker' end,'evidence',(select alignment_status from public.mela_curriculum_frameworks where framework_key='ethiopia_national_alignment'),'required','verified','why','Mela should not claim official curriculum alignment until authoritative sources and educators verify the mapping.'),
    jsonb_build_object('key','content_objective_links','title','Learning content linked to objectives','status',case when v_trace_links>0 then 'foundation' else 'gap' end,'evidence',v_trace_links,'required','>0 pilot links','why','Learners need a clear chain from lesson/practice/assessment to objective and mastery evidence.'),
    jsonb_build_object('key','mastery_engine','title','Evidence-based mastery engine','status',case when to_regprocedure('public.get_my_mastery_engine()') is not null then 'ready' else 'gap' end,'evidence',(select count(*) from public.learning_competencies where content_status<>'retired'),'required',36,'why','The platform must know what the learner can do, not just what they opened.'),
    jsonb_build_object('key','diagnostic_catchup','title','Diagnostic and catch-up loop','status',case when to_regclass('public.learner_catchup_plans') is not null then 'foundation' else 'gap' end,'evidence',(select count(*) from public.learner_catchup_plans),'required','pilot validation','why','Value comes from closing learning gaps, especially before repeated failure.'),
    jsonb_build_object('key','teacher_loop','title','Verified educator evidence loop','status',case when to_regclass('public.educator_observations') is not null then 'foundation' else 'gap' end,'evidence',v_real_educators,'required','real pilot educators','why','Teachers must remain in the loop and be able to add trusted evidence and interventions.'),
    jsonb_build_object('key','project_evidence','title','Projects and authentic evidence','status',case when to_regclass('public.learner_projects') is not null then 'foundation' else 'gap' end,'evidence',(select count(*) from public.learner_projects where verified),'required','real learner projects','why','Real-world application differentiates Mela from passive content libraries.'),
    jsonb_build_object('key','passport','title','Portable learner evidence','status',case when to_regprocedure('public.get_my_learner_passport_v2()') is not null then 'ready' else 'gap' end,'evidence',(select count(*) from public.verified_skills where verified),'required','real verified evidence','why','Learners need portable proof of mastery, projects and skills across stages.'),
    jsonb_build_object('key','pathways','title','Education-to-next-step planning','status',case when to_regprocedure('public.get_my_opportunity_graph()') is not null then 'ready' else 'gap' end,'evidence',(select count(*) from public.opportunity_graph_nodes where active),'required','connected pathways','why','Learning should lead to transparent next steps, not dead ends.'),
    jsonb_build_object('key','outcomes','title','Outcome measurement','status',case when v_outcomes>=12 then 'ready' else 'gap' end,'evidence',v_outcomes,'required',12,'why','Mela must demonstrate learning growth, gap closure, transitions and equity rather than vanity metrics.'),
    jsonb_build_object('key','institution_partners','title','Real education-institution pilots','status',case when v_verified_edu_partners>0 then 'pilot' else 'external_blocker' end,'evidence',v_verified_edu_partners,'required','at least one verified school/TVET/university pilot','why','Sector impact cannot be proven with synthetic data alone.'),
    jsonb_build_object('key','five_languages','title','Five-language platform contract','status',case when v_langs=5 then 'foundation' else 'gap' end,'evidence',v_langs,'required',5,'why','Language choice should affect the full learning experience while verified assessments remain human-certified.'),
    jsonb_build_object('key','offline','title','Low-bandwidth/offline continuity','status',case when v_published_offline>0 then 'pilot' else 'gap' end,'evidence',v_published_offline,'required','published reviewed packs','why','Mela needs to work for learners with intermittent connectivity, not only strong broadband.'),
    jsonb_build_object('key','real_learners','title','Real learner pilot evidence','status',case when v_real_learners>=30 then 'pilot' else 'external_blocker' end,'evidence',v_real_learners,'required','30+ real pilot learners before impact claims','why','Impact claims require real learners and baseline/follow-up evidence.'),
    jsonb_build_object('key','safety','title','Age/stage safety gates','status',case when to_regprocedure('public.my_audience_feature_access(text)') is not null then 'ready' else 'gap' end,'evidence','server-side feature matrix','required','enforced','why','School learning must be separated from adult work, money and direct-contact workflows.')
  );

  return jsonb_build_object(
    'generated_at',now(),
    'value_thesis','Mela creates value when it measurably closes learning gaps, builds verified capability, improves transitions and expands equitable access.',
    'checks',v_checks,
    'summary',jsonb_build_object(
      'ready_or_foundation',(select count(*) from jsonb_array_elements(v_checks) x where x->>'status' in ('ready','foundation','pilot')),
      'gaps',(select count(*) from jsonb_array_elements(v_checks) x where x->>'status'='gap'),
      'external_blockers',(select count(*) from jsonb_array_elements(v_checks) x where x->>'status'='external_blocker'),
      'real_learners',v_real_learners,
      'verified_real_educators',v_real_educators,
      'verified_education_partners',v_verified_edu_partners,
      'published_offline_packs',v_published_offline,
      'published_curriculum_objectives',v_objectives,
      'content_objective_links',v_trace_links,
      'defined_outcome_metrics',v_outcomes,
      'enabled_languages',v_langs
    )
  );
end;
$$;

revoke all on function public.get_my_curriculum_map() from public;
revoke all on function public.get_my_learning_home_v4() from public;
revoke all on function public.admin_education_value_readiness() from public;
grant execute on function public.get_my_curriculum_map() to authenticated;
grant execute on function public.get_my_learning_home_v4() to authenticated;
grant execute on function public.admin_education_value_readiness() to authenticated;

;
