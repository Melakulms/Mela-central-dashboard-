-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260814205935
create table if not exists public.mela_core_capabilities (
  capability_key text primary key,
  title text not null,
  description text not null,
  benchmark_countries text[] not null default '{}',
  evidence_examples text[] not null default '{}',
  display_order smallint not null,
  active boolean not null default true,
  updated_at timestamptz not null default now()
);

create table if not exists public.learning_competency_capabilities (
  competency_id uuid not null references public.learning_competencies(id) on delete cascade,
  capability_key text not null references public.mela_core_capabilities(capability_key) on delete cascade,
  weight numeric(5,2) not null default 1.00 check (weight > 0 and weight <= 1),
  primary key (competency_id, capability_key)
);

create table if not exists public.education_benchmark_adaptations (
  id uuid primary key default gen_random_uuid(),
  country_code text not null references public.education_benchmark_systems(country_code) on delete cascade,
  engine_key text not null references public.mela_education_engines(engine_key) on delete cascade,
  practice_key text not null,
  source_practice text not null,
  mela_adaptation text not null,
  target_stages text[] not null default '{}',
  product_surface text not null,
  success_metric text not null,
  priority smallint not null default 3 check (priority between 1 and 5),
  implementation_status text not null default 'foundation' check (implementation_status in ('planned','foundation','partial','implemented','pilot')),
  active boolean not null default true,
  updated_at timestamptz not null default now(),
  unique (country_code, practice_key)
);

create index if not exists education_benchmark_adaptations_engine_idx
  on public.education_benchmark_adaptations(engine_key, priority desc);

create table if not exists public.mela_learning_cycle_steps (
  step_key text primary key,
  step_order smallint not null unique,
  title text not null,
  purpose text not null,
  default_route_key text,
  benchmark_countries text[] not null default '{}',
  target_stages text[] not null default '{}',
  completion_signals text[] not null default '{}',
  active boolean not null default true,
  updated_at timestamptz not null default now()
);

create table if not exists public.institution_outcome_snapshots (
  id uuid primary key default gen_random_uuid(),
  partner_organization_id uuid not null references public.sector_partner_organizations(id) on delete cascade,
  stage_key text references public.education_audience_stages(stage_key),
  period_start date not null,
  period_end date not null,
  learner_count integer not null default 0 check (learner_count >= 0),
  average_mastery numeric(6,2),
  mastery_growth numeric(6,2),
  intervention_rate numeric(6,2),
  project_completion_rate numeric(6,2),
  transition_success_rate numeric(6,2),
  placement_rate numeric(6,2),
  equity_breakdown jsonb not null default '{}'::jsonb,
  evidence_note text,
  computed_at timestamptz not null default now(),
  check (period_end >= period_start),
  unique (partner_organization_id, stage_key, period_start, period_end)
);

create index if not exists institution_outcomes_org_period_idx
  on public.institution_outcome_snapshots(partner_organization_id, period_end desc);

create table if not exists public.learning_offline_packs (
  id uuid primary key default gen_random_uuid(),
  pack_key text not null unique,
  stage_key text not null references public.education_audience_stages(stage_key),
  language_code text not null references public.platform_languages(language_code),
  title text not null,
  description text,
  version integer not null default 1 check (version > 0),
  manifest jsonb not null default '{}'::jsonb,
  estimated_size_bytes bigint check (estimated_size_bytes is null or estimated_size_bytes >= 0),
  content_status text not null default 'draft' check (content_status in ('draft','review','published','retired')),
  published_at timestamptz,
  updated_at timestamptz not null default now()
);

create index if not exists learning_offline_packs_stage_lang_idx
  on public.learning_offline_packs(stage_key, language_code, content_status);

alter table public.mela_core_capabilities enable row level security;
alter table public.learning_competency_capabilities enable row level security;
alter table public.education_benchmark_adaptations enable row level security;
alter table public.mela_learning_cycle_steps enable row level security;
alter table public.institution_outcome_snapshots enable row level security;
alter table public.learning_offline_packs enable row level security;

grant select, insert, update, delete on public.mela_core_capabilities to authenticated, service_role;
grant select, insert, update, delete on public.learning_competency_capabilities to authenticated, service_role;
grant select, insert, update, delete on public.education_benchmark_adaptations to authenticated, service_role;
grant select, insert, update, delete on public.mela_learning_cycle_steps to authenticated, service_role;
grant select, insert, update, delete on public.institution_outcome_snapshots to authenticated, service_role;
grant select, insert, update, delete on public.learning_offline_packs to authenticated, service_role;

create policy mela_core_capabilities_read on public.mela_core_capabilities
  for select to authenticated using (active);
create policy mela_core_capabilities_admin_write on public.mela_core_capabilities
  for all to authenticated using (private.is_admin_user()) with check (private.is_admin_user());

create policy learning_competency_capabilities_read on public.learning_competency_capabilities
  for select to authenticated using (true);
create policy learning_competency_capabilities_admin_write on public.learning_competency_capabilities
  for all to authenticated using (private.is_admin_user()) with check (private.is_admin_user());

create policy benchmark_adaptations_read on public.education_benchmark_adaptations
  for select to authenticated using (active);
create policy benchmark_adaptations_admin_write on public.education_benchmark_adaptations
  for all to authenticated using (private.is_admin_user()) with check (private.is_admin_user());

create policy mela_learning_cycle_read on public.mela_learning_cycle_steps
  for select to authenticated using (active);
create policy mela_learning_cycle_admin_write on public.mela_learning_cycle_steps
  for all to authenticated using (private.is_admin_user()) with check (private.is_admin_user());

create policy institution_outcomes_read on public.institution_outcome_snapshots
  for select to authenticated
  using (
    private.is_admin_user()
    or private.has_sector_partner_membership(partner_organization_id, (select auth.uid()), false)
  );
create policy institution_outcomes_admin_write on public.institution_outcome_snapshots
  for all to authenticated using (private.is_admin_user()) with check (private.is_admin_user());

create policy offline_packs_read on public.learning_offline_packs
  for select to authenticated using (content_status = 'published' or private.is_admin_user());
create policy offline_packs_admin_write on public.learning_offline_packs
  for all to authenticated using (private.is_admin_user()) with check (private.is_admin_user());

insert into public.mela_core_capabilities(capability_key,title,description,benchmark_countries,evidence_examples,display_order,active)
values
('literacy','Literacy','Understand, evaluate and create meaning across written and multimodal information.',array['IE','CA','FI'],array['reading comprehension','clear writing','source interpretation'],10,true),
('numeracy','Numeracy','Use number, quantity, patterns and mathematical reasoning in real situations.',array['SG','JP','KR','VN'],array['calculation','mathematical modelling','data interpretation'],20,true),
('scientific_reasoning','Scientific Reasoning','Ask questions, use evidence, test explanations and reason about the natural and designed world.',array['JP','SG','EE','CA'],array['experiments','evidence claims','scientific explanation'],30,true),
('critical_thinking','Critical Thinking & Problem Solving','Break down unfamiliar problems, compare evidence, reason through alternatives and make defensible decisions.',array['EE','AU','NZ','DK'],array['problem decomposition','evidence evaluation','solution comparison'],40,true),
('creativity','Creativity & Innovation','Generate, test, improve and communicate original ideas and useful solutions.',array['NZ','DK','AU','EE'],array['projects','prototypes','creative production'],50,true),
('digital_literacy','Digital Literacy','Use digital tools safely, effectively and productively for learning, work and participation.',array['EE','UY','SE','LT'],array['digital research','productivity tools','digital safety'],60,true),
('ai_literacy','AI Literacy','Understand, use and critically evaluate AI systems with appropriate safety, ethics and human judgment.',array['EE','SG','KR'],array['prompting with verification','AI limitations','responsible use'],70,true),
('communication','Communication','Express ideas clearly, listen, adapt messages to audiences and communicate across languages and media.',array['CA','NZ','AU','FI'],array['presentation','discussion','multilingual communication'],80,true),
('collaboration_leadership','Collaboration & Leadership','Work responsibly with others, contribute to teams, resolve differences and lead when appropriate.',array['DK','JP','FI','NZ'],array['team projects','peer feedback','leadership roles'],90,true),
('entrepreneurship_financial','Entrepreneurship & Financial Literacy','Recognize opportunities, create value, understand money and make responsible economic decisions.',array['CH','NL','SG','CZ'],array['budgeting','business models','value creation'],100,true)
on conflict (capability_key) do update set
  title=excluded.title,description=excluded.description,benchmark_countries=excluded.benchmark_countries,
  evidence_examples=excluded.evidence_examples,display_order=excluded.display_order,active=excluded.active,updated_at=now();

insert into public.learning_competency_capabilities(competency_id,capability_key,weight)
select id,'literacy',0.60 from public.learning_competencies where domain_key='literacy'
on conflict do nothing;
insert into public.learning_competency_capabilities(competency_id,capability_key,weight)
select id,'communication',0.40 from public.learning_competencies where domain_key='literacy'
on conflict do nothing;
insert into public.learning_competency_capabilities(competency_id,capability_key,weight)
select id,'numeracy',1.00 from public.learning_competencies where domain_key='numeracy'
on conflict do nothing;
insert into public.learning_competency_capabilities(competency_id,capability_key,weight)
select id,'scientific_reasoning',1.00 from public.learning_competencies where domain_key='science'
on conflict do nothing;
insert into public.learning_competency_capabilities(competency_id,capability_key,weight)
select id,'scientific_reasoning',0.50 from public.learning_competencies where domain_key='stem'
on conflict do nothing;
insert into public.learning_competency_capabilities(competency_id,capability_key,weight)
select id,'critical_thinking',0.50 from public.learning_competencies where domain_key='stem'
on conflict do nothing;
insert into public.learning_competency_capabilities(competency_id,capability_key,weight)
select id,'digital_literacy',0.70 from public.learning_competencies where domain_key='digital'
on conflict do nothing;
insert into public.learning_competency_capabilities(competency_id,capability_key,weight)
select id,'ai_literacy',0.30 from public.learning_competencies where domain_key='digital'
on conflict do nothing;
insert into public.learning_competency_capabilities(competency_id,capability_key,weight)
select id,'ai_literacy',1.00 from public.learning_competencies where domain_key='ai'
on conflict do nothing;
insert into public.learning_competency_capabilities(competency_id,capability_key,weight)
select id,'creativity',1.00 from public.learning_competencies where domain_key='creativity'
on conflict do nothing;
insert into public.learning_competency_capabilities(competency_id,capability_key,weight)
select id,'critical_thinking',0.35 from public.learning_competencies where domain_key in ('problem_solving','technical','domain')
on conflict do nothing;
insert into public.learning_competency_capabilities(competency_id,capability_key,weight)
select id,'critical_thinking',0.35 from public.learning_competencies where domain_key='projects'
on conflict do nothing;
insert into public.learning_competency_capabilities(competency_id,capability_key,weight)
select id,'creativity',0.30 from public.learning_competencies where domain_key='projects'
on conflict do nothing;
insert into public.learning_competency_capabilities(competency_id,capability_key,weight)
select id,'collaboration_leadership',0.35 from public.learning_competencies where domain_key='projects'
on conflict do nothing;
insert into public.learning_competency_capabilities(competency_id,capability_key,weight)
select id,'literacy',0.45 from public.learning_competencies where domain_key='academic'
on conflict do nothing;
insert into public.learning_competency_capabilities(competency_id,capability_key,weight)
select id,'critical_thinking',0.55 from public.learning_competencies where domain_key='academic'
on conflict do nothing;
insert into public.learning_competency_capabilities(competency_id,capability_key,weight)
select id,'entrepreneurship_financial',1.00 from public.learning_competencies where domain_key='life'
on conflict do nothing;
insert into public.learning_competency_capabilities(competency_id,capability_key,weight)
select id,'communication',0.45 from public.learning_competencies where domain_key in ('work_readiness','professional')
on conflict do nothing;
insert into public.learning_competency_capabilities(competency_id,capability_key,weight)
select id,'collaboration_leadership',0.55 from public.learning_competencies where domain_key in ('work_readiness','professional')
on conflict do nothing;

insert into public.education_benchmark_adaptations(country_code,engine_key,practice_key,source_practice,mela_adaptation,target_stages,product_surface,success_metric,priority,implementation_status,active)
values
('SG','mastery','mastery_before_acceleration','Coherent curriculum, strong fundamentals and mastery-oriented progression.','Require evidence of competency before recommending acceleration; use diagnostics and catch-up when mastery is weak.',array['school_1_6','school_7_8','school_9_10','school_11_12'],'Mastery Engine','share of learners reaching target mastery without hidden prerequisite gaps',5,'implemented',true),
('EE','teacher_copilot','digital_by_design','Digital competence, school autonomy and technology integrated into learning.','Give teachers AI-supported planning, multilingual resources and learner-gap analytics while keeping teachers in control.',array['school_1_6','school_7_8','school_9_10','school_11_12'],'Teacher Copilot','teacher adoption plus improvement in targeted learner mastery',5,'foundation',true),
('FI','diagnostic_catchup','early_support_before_failure','Early support, equity and professional teacher judgment.','Trigger targeted catch-up before repeated failure and show teachers simple intervention signals instead of waiting for terminal exams.',array['school_1_6','school_7_8','school_9_10','school_11_12'],'Diagnostic & Catch-Up','reduction in unresolved foundational gaps and repeat intervention cycles',5,'foundation',true),
('JP','teacher_copilot','lesson_study_loop','Collaborative teacher improvement and disciplined learning routines.','Create teacher reflection, observation and shared lesson-improvement loops around classroom evidence.',array['school_1_6','school_7_8','school_9_10','school_11_12'],'Teacher Copilot','number of evidence-backed lesson improvements and learner gains',4,'foundation',true),
('KR','mela_next','high_expectations_transition','High expectations, strong STEM and digital readiness with clear tertiary aspiration.','Use transparent readiness maps and transition planning without importing excessive exam-pressure culture.',array['school_9_10','school_11_12','college_tvet','university'],'Mela Next','percentage of learners with an active next-step plan and completed readiness milestones',4,'partial',true),
('CA','passport','inclusive_portable_evidence','Inclusive pathways and flexible local implementation within strong outcomes.','Keep a portable learner record that recognizes verified mastery, projects, languages and achievements across stages.',array['school_1_6','school_7_8','school_9_10','school_11_12','college_tvet','university'],'Learner Passport','percentage of active learners with multi-source verified evidence',5,'implemented',true),
('AU','institution_outcomes','capabilities_and_outcomes','General capabilities integrated across subjects and system-level outcome monitoring.','Track Mela core capabilities across learning areas and give institutions outcome dashboards focused on mastery and progression.',array['school_1_6','school_7_8','school_9_10','school_11_12','college_tvet','university'],'Mela Outcomes','capability growth, intervention closure and transition outcomes by institution',5,'foundation',true),
('NZ','projects_impact','learner_agency_projects','Learner agency, local curriculum flexibility and project learning.','Use Ethiopian community challenges and learner choice to produce portfolio evidence rather than passive completion.',array['school_7_8','school_9_10','school_11_12','college_tvet','university'],'Projects & Impact','verified project completion and demonstrated capability growth',4,'partial',true),
('IE','mastery','literacy_fundamentals','Strong reading outcomes and sustained attention to fundamentals.','Protect literacy foundations across all stages and make weak comprehension visible in the mastery map.',array['school_1_6','school_7_8','school_9_10'],'Mastery Engine','literacy mastery and reading-gap closure',4,'implemented',true),
('CH','opportunity_graph','dual_vet_employer_link','Employer-linked vocational education and multiple respected post-school routes.','Connect competencies to real TVET, apprenticeship, internship, employer challenge and job pathways.',array['school_11_12','college_tvet','university'],'Opportunity Graph','qualified transitions into verified education-to-work opportunities',5,'implemented',true),
('NL','mela_next','multiple_respected_pathways','Clear differentiated academic and vocational pathways.','Show multiple routes with prerequisites, reversibility and bridge options so learners are guided without being permanently tracked.',array['school_9_10','school_11_12'],'Mela Next','learners comparing at least two viable pathways before transition decisions',5,'partial',true),
('DK','projects_impact','collaborative_project_learning','Collaboration, student voice and broad project-oriented learning.','Score teamwork and problem solving through authentic projects and Arena formats, not only quizzes.',array['school_7_8','school_9_10','school_11_12','college_tvet','university'],'Projects & Arena','verified teamwork/project evidence per active learner',4,'partial',true),
('SE','family_support','agency_and_digital_citizenship','Student agency, inclusive support and digital citizenship.','Give families supportive progress summaries and teach responsible digital participation without surveillance.',array['school_1_6','school_7_8','school_9_10','school_11_12'],'Mela Family','guardian engagement plus learner digital-safety competency',3,'foundation',true),
('PT','family_support','belonging_and_inclusion','Belonging, inclusion and sustained system improvement.','Add belonging/support signals and family-facing interventions before disengagement becomes failure.',array['school_1_6','school_7_8','school_9_10','school_11_12'],'Mela Family','improved support closure and learner re-engagement',4,'foundation',true),
('PL','mastery','clear_standards_support','Clear standards, solid core knowledge and historically strong improvement.','Keep explicit competency expectations and intervene before repeating or abandoning a pathway.',array['school_1_6','school_7_8','school_9_10','school_11_12'],'Mastery Engine','percentage meeting stage competency targets',4,'implemented',true),
('CZ','mela_next','academic_plus_vocational_routes','Strong core academics alongside vocational pathways.','Give learners technical and academic next steps with prerequisite maps and bridge learning.',array['school_9_10','school_11_12','college_tvet'],'Mela Next','transition completion across both academic and technical routes',4,'partial',true),
('SI','mela_next','balanced_academic_technical','Broad curriculum with solid mathematics/science and technical education.','Keep academic and technical competencies visible in one passport rather than treating vocational routes as second class.',array['school_9_10','school_11_12','college_tvet'],'Learner Passport & Mela Next','balanced verified evidence across academic and technical capabilities',3,'partial',true),
('LT','mela_lite','resilient_digital_continuity','Digital transformation combined with system resilience.','Design downloadable learning packs and continuity mechanisms for intermittent connectivity, with progress syncing later.',array['school_1_6','school_7_8','school_9_10','school_11_12','college_tvet','university'],'Mela Lite','successful learning continuation during low-connectivity periods',4,'foundation',true),
('UY','mela_lite','digital_equity_ecosystem','National digital access evolved into a broader learning ecosystem with teacher support.','Treat connectivity, content, teacher support and platform usability as one equity system rather than a device-only solution.',array['school_1_6','school_7_8','school_9_10','school_11_12'],'Mela Lite','regional usage and completion parity between low- and high-connectivity learners',5,'foundation',true),
('VN','diagnostic_catchup','strong_fundamentals_low_resource','Clear learning expectations, textbook access, teacher development and strong fundamentals under resource constraints.','Prioritize level-appropriate foundational content, frequent checks for understanding and teacher-visible gaps.',array['school_1_6','school_7_8','school_9_10'],'Diagnostic & Catch-Up','foundational literacy/numeracy mastery gains at low delivery cost',5,'foundation',true)
on conflict (country_code,practice_key) do update set
  engine_key=excluded.engine_key,source_practice=excluded.source_practice,mela_adaptation=excluded.mela_adaptation,
  target_stages=excluded.target_stages,product_surface=excluded.product_surface,success_metric=excluded.success_metric,
  priority=excluded.priority,implementation_status=excluded.implementation_status,active=excluded.active,updated_at=now();

insert into public.mela_learning_cycle_steps(step_key,step_order,title,purpose,default_route_key,benchmark_countries,target_stages,completion_signals,active)
values
('diagnose',10,'Diagnose','Find the learner actual level before prescribing content.','mastery',array['FI','SG','VN'],array['school_1_6','school_7_8','school_9_10','school_11_12','college_tvet','university'],array['diagnostic completed','priority gaps identified'],true),
('learn',20,'Learn','Teach the next appropriate concept using stage- and language-appropriate content.','academy',array['SG','IE','VN'],array['school_1_6','school_7_8','school_9_10','school_11_12','college_tvet','university'],array['lesson evidence recorded','concept exposure completed'],true),
('practice',30,'Practice','Use retrieval, worked examples and targeted practice until performance stabilizes.','practice',array['SG','JP','PL'],array['school_1_6','school_7_8','school_9_10','school_11_12','college_tvet','university'],array['practice attempts','stable target score'],true),
('support',40,'AI + Teacher Support','Use AI and teacher intervention to explain gaps differently, not simply repeat the same lesson.','academy',array['EE','FI','JP'],array['school_1_6','school_7_8','school_9_10','school_11_12','college_tvet','university'],array['intervention evidence','learner reflection'],true),
('build',50,'Build & Apply','Turn knowledge into projects, challenges and authentic problem solving.','arena',array['NZ','DK','AU'],array['school_7_8','school_9_10','school_11_12','college_tvet','university'],array['project or challenge evidence','teamwork/problem-solving evidence'],true),
('prove',60,'Prove','Use assessments and verified evidence to determine demonstrated competence.','assessments',array['SG','AU','IE'],array['school_11_12','college_tvet','university'],array['verified assessment or reviewed evidence'],true),
('passport',70,'Record in Passport','Convert trusted evidence into a portable learner record.','passport',array['CA','AU','NZ'],array['school_1_6','school_7_8','school_9_10','school_11_12','college_tvet','university'],array['passport updated','evidence source linked'],true),
('transition',80,'Connect to Next Step','Use evidence to recommend the next learning, scholarship, TVET, university, project or work opportunity.','mela-next',array['CH','NL','KR','CZ'],array['school_9_10','school_11_12','college_tvet','university'],array['transition plan','qualified opportunity action'],true)
on conflict (step_key) do update set
  step_order=excluded.step_order,title=excluded.title,purpose=excluded.purpose,default_route_key=excluded.default_route_key,
  benchmark_countries=excluded.benchmark_countries,target_stages=excluded.target_stages,completion_signals=excluded.completion_signals,
  active=excluded.active,updated_at=now();

update public.mela_education_engines
set implementation_status='implemented',
    current_assets=jsonb_build_object('rpc','get_my_learner_passport_v2','existing','Career Passport + mastery + verified skills + projects','benchmark_layer','education_benchmark_adaptations'),
    updated_at=now()
where engine_key='passport';

update public.mela_education_engines
set implementation_status='foundation',
    current_assets=jsonb_build_object('table','institution_outcome_snapshots','benchmark_layer','education_benchmark_adaptations','principle','measure mastery, growth, intervention closure and transitions rather than vanity metrics'),
    updated_at=now()
where engine_key='institution_outcomes';

update public.mela_education_engines
set implementation_status='foundation',
    current_assets=jsonb_build_object('table','learning_offline_packs','benchmark_layer','education_benchmark_adaptations','next','author reviewed low-bandwidth content packs and client sync implementation'),
    updated_at=now()
where engine_key='mela_lite';

create or replace function public.get_mela_benchmark_blueprint_v2()
returns jsonb
language sql
stable
set search_path=''
as $$
select jsonb_build_object(
  'benchmark_country_count',(select count(*) from public.education_benchmark_systems where active),
  'systems',(select coalesce(jsonb_agg(to_jsonb(b) order by b.country_name),'[]'::jsonb) from public.education_benchmark_systems b where b.active),
  'engines',(select coalesce(jsonb_agg(to_jsonb(e) order by e.display_order),'[]'::jsonb) from public.mela_education_engines e),
  'adaptations',(select coalesce(jsonb_agg(to_jsonb(a) order by a.priority desc,b.country_name),'[]'::jsonb) from public.education_benchmark_adaptations a join public.education_benchmark_systems b on b.country_code=a.country_code where a.active),
  'core_capabilities',(select coalesce(jsonb_agg(to_jsonb(c) order by c.display_order),'[]'::jsonb) from public.mela_core_capabilities c where c.active),
  'learning_cycle',(select coalesce(jsonb_agg(to_jsonb(s) order by s.step_order),'[]'::jsonb) from public.mela_learning_cycle_steps s where s.active),
  'coverage',jsonb_build_object(
    'adaptation_count',(select count(*) from public.education_benchmark_adaptations where active),
    'countries_with_adaptations',(select count(distinct country_code) from public.education_benchmark_adaptations where active),
    'engines_with_adaptations',(select count(distinct engine_key) from public.education_benchmark_adaptations where active)
  )
);
$$;

revoke all on function public.get_mela_benchmark_blueprint_v2() from public;
grant execute on function public.get_mela_benchmark_blueprint_v2() to authenticated, service_role;

create or replace function public.get_my_growth_plan_v1()
returns jsonb
language plpgsql
stable
set search_path=''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_stage text;
  v_stage_title text;
  v_mastery jsonb;
  v_diag_count integer;
  v_recent_project_count integer;
  v_actions jsonb := '[]'::jsonb;
begin
  if v_uid is null then raise exception 'authentication required'; end if;

  select p.education_stage_key, s.title
    into v_stage, v_stage_title
  from public.profiles p
  left join public.education_audience_stages s on s.stage_key=p.education_stage_key
  where p.id=v_uid;

  if v_stage is null then raise exception 'education stage required'; end if;

  v_mastery := public.get_my_mastery_engine();

  select count(*) into v_diag_count
  from public.learner_diagnostic_sessions
  where user_id=v_uid and status='completed' and completed_at >= now()-interval '120 days';

  select count(*) into v_recent_project_count
  from public.learner_projects
  where user_id=v_uid and created_at >= now()-interval '120 days' and status in ('submitted','verified','completed');

  if v_diag_count=0 then
    v_actions := v_actions || jsonb_build_array(jsonb_build_object('priority',1,'action_key','diagnostic','title','Check my current level','route_key','mastery','reason','No completed diagnostic in the last 120 days'));
  end if;

  v_actions := v_actions || jsonb_build_array(jsonb_build_object('priority',2,'action_key','targeted_practice','title','Work on my weakest competency','route_key','practice','reason','Use the Mastery Engine to target the lowest-scoring competency'));

  if v_stage in ('school_7_8','school_9_10','school_11_12','college_tvet','university') and v_recent_project_count=0 then
    v_actions := v_actions || jsonb_build_array(jsonb_build_object('priority',3,'action_key','build_project','title','Build something that proves what I can do','route_key','arena','reason','No recent project evidence in the last 120 days'));
  end if;

  v_actions := v_actions || jsonb_build_array(jsonb_build_object('priority',4,'action_key','passport','title','Strengthen my Learner Passport','route_key','passport','reason','Convert learning and project evidence into a portable record'));

  if v_stage in ('school_9_10','school_11_12','college_tvet','university') then
    v_actions := v_actions || jsonb_build_array(jsonb_build_object('priority',5,'action_key','transition','title','Plan my next step','route_key','mela-next','reason','This stage should connect learning to the next education, scholarship or work pathway'));
  end if;

  return jsonb_build_object(
    'stage_key',v_stage,
    'stage_title',v_stage_title,
    'overall_mastery',coalesce((v_mastery->>'overall_score')::numeric,0),
    'mastery',v_mastery,
    'core_capabilities',coalesce((
      select jsonb_agg(jsonb_build_object(
        'capability_key',q.capability_key,
        'title',q.title,
        'score',q.score,
        'evidence_weight',q.evidence_weight
      ) order by q.display_order)
      from (
        select c.capability_key,c.title,c.display_order,
               round(coalesce(sum(coalesce(m.mastery_score,0)*map.weight)/nullif(sum(map.weight),0),0),2) as score,
               round(coalesce(sum(map.weight),0),2) as evidence_weight
        from public.mela_core_capabilities c
        left join public.learning_competency_capabilities map on map.capability_key=c.capability_key
        left join public.learning_competencies lc on lc.id=map.competency_id and lc.stage_key=v_stage and lc.content_status<>'retired'
        left join public.learner_mastery_records m on m.competency_id=lc.id and m.user_id=v_uid
        where c.active
        group by c.capability_key,c.title,c.display_order
      ) q
    ),'[]'::jsonb),
    'priority_gaps',coalesce((
      select jsonb_agg(x order by (x->>'score')::numeric asc)
      from (
        select jsonb_build_object('competency_id',lc.id,'title',lc.title,'domain',lc.domain_title,'score',coalesce(m.mastery_score,0),'level',coalesce(m.mastery_level,'not_started')) x
        from public.learning_competencies lc
        left join public.learner_mastery_records m on m.competency_id=lc.id and m.user_id=v_uid
        where lc.stage_key=v_stage and lc.content_status<>'retired'
        order by coalesce(m.mastery_score,0) asc,lc.display_order
        limit 5
      ) g
    ),'[]'::jsonb),
    'next_actions',v_actions,
    'learning_cycle',(select coalesce(jsonb_agg(jsonb_build_object('step_key',s.step_key,'title',s.title,'route_key',s.default_route_key,'purpose',s.purpose) order by s.step_order),'[]'::jsonb) from public.mela_learning_cycle_steps s where s.active and v_stage=any(s.target_stages))
  );
end;
$$;

revoke all on function public.get_my_growth_plan_v1() from public;
grant execute on function public.get_my_growth_plan_v1() to authenticated, service_role;

;
