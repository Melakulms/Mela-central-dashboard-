-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260814203813
create table if not exists public.learning_competencies (
  id uuid primary key default gen_random_uuid(),
  competency_key text not null unique,
  stage_key text not null references public.education_audience_stages(stage_key) on update cascade on delete restrict,
  domain_key text not null,
  domain_title text not null,
  title text not null,
  description text not null,
  display_order smallint not null default 10,
  target_score numeric(5,2) not null default 80 check(target_score between 0 and 100),
  content_status text not null default 'framework' check(content_status in ('framework','educator_review','active','retired')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.learner_mastery_records (
  user_id uuid not null references public.profiles(id) on delete cascade,
  competency_id uuid not null references public.learning_competencies(id) on delete cascade,
  mastery_score numeric(5,2) not null default 0 check(mastery_score between 0 and 100),
  mastery_level text not null default 'not_started' check(mastery_level in ('not_started','emerging','developing','proficient','mastered')),
  confidence_score numeric(5,2) not null default 0 check(confidence_score between 0 and 100),
  evidence_count integer not null default 0,
  verified_evidence_count integer not null default 0,
  first_evidence_at timestamptz,
  last_evidence_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key(user_id,competency_id)
);

create table if not exists public.learner_mastery_evidence (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  competency_id uuid not null references public.learning_competencies(id) on delete cascade,
  evidence_type text not null check(evidence_type in ('practice','assessment','project','teacher_observation','portfolio','self_reflection','external_verification')),
  score numeric(5,2) not null check(score between 0 and 100),
  weight numeric(5,2) not null default 1 check(weight > 0 and weight <= 10),
  verified boolean not null default false,
  verified_by uuid references public.profiles(id) on delete set null,
  source_table text,
  source_id uuid,
  evidence_url text,
  notes text,
  created_at timestamptz not null default now()
);

create table if not exists public.learner_projects (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  stage_key text references public.education_audience_stages(stage_key) on update cascade on delete set null,
  title text not null,
  description text,
  project_type text not null default 'learning_project' check(project_type in ('learning_project','community_project','challenge','research','technical_project','creative_project')),
  status text not null default 'draft' check(status in ('draft','in_progress','submitted','verified','archived')),
  evidence_url text,
  reflection text,
  verified boolean not null default false,
  verified_by uuid references public.profiles(id) on delete set null,
  verified_at timestamptz,
  is_public boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.learner_project_competencies (
  project_id uuid not null references public.learner_projects(id) on delete cascade,
  competency_id uuid not null references public.learning_competencies(id) on delete cascade,
  primary key(project_id,competency_id)
);

create table if not exists public.educator_profiles (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  partner_organization_id uuid not null references public.sector_partner_organizations(id) on delete cascade,
  role_title text not null default 'Educator',
  subject_areas text[] not null default '{}',
  stage_keys text[] not null default '{}',
  verified boolean not null default true,
  verified_by uuid references public.profiles(id) on delete set null,
  verified_at timestamptz,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.educator_classrooms (
  id uuid primary key default gen_random_uuid(),
  educator_id uuid not null references public.educator_profiles(user_id) on delete cascade,
  partner_organization_id uuid not null references public.sector_partner_organizations(id) on delete cascade,
  title text not null,
  stage_key text not null references public.education_audience_stages(stage_key) on update cascade on delete restrict,
  subject text,
  join_code text not null unique default upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.educator_classroom_members (
  classroom_id uuid not null references public.educator_classrooms(id) on delete cascade,
  learner_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'active' check(status in ('active','left','removed')),
  joined_at timestamptz not null default now(),
  primary key(classroom_id,learner_id)
);

create table if not exists public.educator_observations (
  id uuid primary key default gen_random_uuid(),
  classroom_id uuid not null references public.educator_classrooms(id) on delete cascade,
  educator_id uuid not null references public.educator_profiles(user_id) on delete cascade,
  learner_id uuid not null references public.profiles(id) on delete cascade,
  competency_id uuid references public.learning_competencies(id) on delete set null,
  observation_type text not null default 'mastery_observation' check(observation_type in ('mastery_observation','intervention','strength','project_review','learning_note')),
  score numeric(5,2) check(score between 0 and 100),
  notes text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.mela_transition_plans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  goal_type text not null check(goal_type in ('next_grade','college_tvet','university','career_path','scholarship','employment','entrepreneurship')),
  goal_title text not null,
  career_path_id uuid references public.career_paths(id) on delete set null,
  status text not null default 'active' check(status in ('active','completed','paused','archived')),
  target_date date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists mela_transition_one_active_goal_uidx on public.mela_transition_plans(user_id) where status='active';

create table if not exists public.mela_transition_steps (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.mela_transition_plans(id) on delete cascade,
  step_order smallint not null,
  step_type text not null check(step_type in ('learn','practice','project','verify','research','apply','prepare','connect')),
  title text not null,
  description text,
  status text not null default 'not_started' check(status in ('not_started','in_progress','completed','skipped')),
  route_key text,
  due_date date,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  unique(plan_id,step_order)
);

create table if not exists public.opportunity_graph_nodes (
  id uuid primary key default gen_random_uuid(),
  node_key text not null unique,
  node_type text not null check(node_type in ('education_stage','learning_track','competency_domain','career_path','destination','opportunity_type')),
  stage_key text references public.education_audience_stages(stage_key) on update cascade on delete set null,
  career_path_id uuid references public.career_paths(id) on delete cascade,
  title text not null,
  description text,
  route_key text,
  metadata jsonb not null default '{}'::jsonb,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.opportunity_graph_edges (
  id uuid primary key default gen_random_uuid(),
  from_node_id uuid not null references public.opportunity_graph_nodes(id) on delete cascade,
  to_node_id uuid not null references public.opportunity_graph_nodes(id) on delete cascade,
  relationship text not null check(relationship in ('progresses_to','prepares_for','opens','specializes_into','can_lead_to','supported_by')),
  weight numeric(5,2) not null default 1,
  rationale text,
  active boolean not null default true,
  unique(from_node_id,to_node_id,relationship)
);

create index if not exists learner_mastery_evidence_user_comp_idx on public.learner_mastery_evidence(user_id,competency_id,created_at desc);
create index if not exists learner_projects_user_idx on public.learner_projects(user_id,created_at desc);
create index if not exists educator_classrooms_educator_idx on public.educator_classrooms(educator_id,active);
create index if not exists educator_members_learner_idx on public.educator_classroom_members(learner_id,status);
create index if not exists educator_observations_learner_idx on public.educator_observations(learner_id,created_at desc);
create index if not exists transition_steps_plan_idx on public.mela_transition_steps(plan_id,step_order);
create index if not exists opportunity_graph_edges_from_idx on public.opportunity_graph_edges(from_node_id);
create index if not exists opportunity_graph_edges_to_idx on public.opportunity_graph_edges(to_node_id);

alter table public.learning_competencies enable row level security;
alter table public.learner_mastery_records enable row level security;
alter table public.learner_mastery_evidence enable row level security;
alter table public.learner_projects enable row level security;
alter table public.learner_project_competencies enable row level security;
alter table public.educator_profiles enable row level security;
alter table public.educator_classrooms enable row level security;
alter table public.educator_classroom_members enable row level security;
alter table public.educator_observations enable row level security;
alter table public.mela_transition_plans enable row level security;
alter table public.mela_transition_steps enable row level security;
alter table public.opportunity_graph_nodes enable row level security;
alter table public.opportunity_graph_edges enable row level security;

create or replace function private.can_educate_learner(p_educator uuid,p_learner uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(
    select 1 from public.educator_profiles ep
    join public.educator_classrooms c on c.educator_id=ep.user_id and c.active
    join public.educator_classroom_members m on m.classroom_id=c.id and m.status='active'
    where ep.user_id=p_educator and ep.verified and ep.active and m.learner_id=p_learner
  );
$$;
revoke all on function private.can_educate_learner(uuid,uuid) from public,anon,authenticated;

drop policy if exists learning_competencies_read on public.learning_competencies;
create policy learning_competencies_read on public.learning_competencies for select to authenticated using (content_status<>'retired');

drop policy if exists learner_mastery_self_or_educator on public.learner_mastery_records;
create policy learner_mastery_self_or_educator on public.learner_mastery_records for select to authenticated using ((select auth.uid())=user_id or private.can_educate_learner((select auth.uid()),user_id) or private.is_admin_user());

drop policy if exists learner_evidence_self_or_educator on public.learner_mastery_evidence;
create policy learner_evidence_self_or_educator on public.learner_mastery_evidence for select to authenticated using ((select auth.uid())=user_id or private.can_educate_learner((select auth.uid()),user_id) or private.is_admin_user());

drop policy if exists learner_projects_self on public.learner_projects;
create policy learner_projects_self on public.learner_projects for all to authenticated using ((select auth.uid())=user_id or private.is_admin_user()) with check ((select auth.uid())=user_id or private.is_admin_user());

drop policy if exists learner_project_comp_self on public.learner_project_competencies;
create policy learner_project_comp_self on public.learner_project_competencies for all to authenticated using (exists(select 1 from public.learner_projects p where p.id=project_id and (p.user_id=(select auth.uid()) or private.is_admin_user()))) with check (exists(select 1 from public.learner_projects p where p.id=project_id and (p.user_id=(select auth.uid()) or private.is_admin_user())));

drop policy if exists educator_profiles_visible on public.educator_profiles;
create policy educator_profiles_visible on public.educator_profiles for select to authenticated using ((select auth.uid())=user_id or private.is_admin_user() or private.has_sector_partner_membership(partner_organization_id,(select auth.uid()),true));
drop policy if exists educator_profiles_self_update on public.educator_profiles;
create policy educator_profiles_self_update on public.educator_profiles for update to authenticated using ((select auth.uid())=user_id) with check ((select auth.uid())=user_id);

drop policy if exists educator_classrooms_visible on public.educator_classrooms;
create policy educator_classrooms_visible on public.educator_classrooms for select to authenticated using (educator_id=(select auth.uid()) or private.is_admin_user() or exists(select 1 from public.educator_classroom_members m where m.classroom_id=id and m.learner_id=(select auth.uid()) and m.status='active'));

drop policy if exists educator_members_visible on public.educator_classroom_members;
create policy educator_members_visible on public.educator_classroom_members for select to authenticated using (learner_id=(select auth.uid()) or private.is_admin_user() or exists(select 1 from public.educator_classrooms c where c.id=classroom_id and c.educator_id=(select auth.uid())));

drop policy if exists educator_observations_visible on public.educator_observations;
create policy educator_observations_visible on public.educator_observations for select to authenticated using (learner_id=(select auth.uid()) or educator_id=(select auth.uid()) or private.is_admin_user());

drop policy if exists transition_plans_self on public.mela_transition_plans;
create policy transition_plans_self on public.mela_transition_plans for all to authenticated using (user_id=(select auth.uid()) or private.is_admin_user()) with check (user_id=(select auth.uid()) or private.is_admin_user());

drop policy if exists transition_steps_self on public.mela_transition_steps;
create policy transition_steps_self on public.mela_transition_steps for all to authenticated using (exists(select 1 from public.mela_transition_plans p where p.id=plan_id and (p.user_id=(select auth.uid()) or private.is_admin_user()))) with check (exists(select 1 from public.mela_transition_plans p where p.id=plan_id and (p.user_id=(select auth.uid()) or private.is_admin_user())));

drop policy if exists opportunity_graph_nodes_read on public.opportunity_graph_nodes;
create policy opportunity_graph_nodes_read on public.opportunity_graph_nodes for select to authenticated using (active);
drop policy if exists opportunity_graph_edges_read on public.opportunity_graph_edges;
create policy opportunity_graph_edges_read on public.opportunity_graph_edges for select to authenticated using (active);

create or replace function private.refresh_learner_mastery(p_user uuid,p_competency uuid)
returns void language plpgsql security definer set search_path='' as $$
declare v_score numeric;v_count int;v_verified int;v_first timestamptz;v_last timestamptz;v_conf numeric;v_level text;
begin
  select coalesce(sum(score*weight*(case when verified then 1 else 0.4 end))/nullif(sum(weight*(case when verified then 1 else 0.4 end)),0),0),count(*),count(*) filter(where verified),min(created_at),max(created_at)
  into v_score,v_count,v_verified,v_first,v_last
  from public.learner_mastery_evidence where user_id=p_user and competency_id=p_competency;
  v_conf:=least(100,coalesce(v_verified,0)*25+greatest(coalesce(v_count,0)-coalesce(v_verified,0),0)*8);
  v_level:=case when v_count=0 then 'not_started' when v_score<40 then 'emerging' when v_score<65 then 'developing' when v_score<85 then 'proficient' else 'mastered' end;
  insert into public.learner_mastery_records(user_id,competency_id,mastery_score,mastery_level,confidence_score,evidence_count,verified_evidence_count,first_evidence_at,last_evidence_at,updated_at)
  values(p_user,p_competency,round(v_score,2),v_level,v_conf,v_count,v_verified,v_first,v_last,now())
  on conflict(user_id,competency_id) do update set mastery_score=excluded.mastery_score,mastery_level=excluded.mastery_level,confidence_score=excluded.confidence_score,evidence_count=excluded.evidence_count,verified_evidence_count=excluded.verified_evidence_count,first_evidence_at=excluded.first_evidence_at,last_evidence_at=excluded.last_evidence_at,updated_at=now();
end;$$;
revoke all on function private.refresh_learner_mastery(uuid,uuid) from public,anon,authenticated;

create or replace function private.trg_refresh_learner_mastery() returns trigger language plpgsql security definer set search_path='' as $$
begin
  if tg_op='DELETE' then perform private.refresh_learner_mastery(old.user_id,old.competency_id);return old;end if;
  perform private.refresh_learner_mastery(new.user_id,new.competency_id);
  if tg_op='UPDATE' and (old.user_id,old.competency_id) is distinct from (new.user_id,new.competency_id) then perform private.refresh_learner_mastery(old.user_id,old.competency_id);end if;
  return new;
end;$$;
revoke all on function private.trg_refresh_learner_mastery() from public,anon,authenticated;
drop trigger if exists trg_refresh_learner_mastery on public.learner_mastery_evidence;
create trigger trg_refresh_learner_mastery after insert or update or delete on public.learner_mastery_evidence for each row execute function private.trg_refresh_learner_mastery();

create or replace function private.trg_observation_to_mastery() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.competency_id is not null and new.score is not null then
  insert into public.learner_mastery_evidence(user_id,competency_id,evidence_type,score,weight,verified,verified_by,source_table,source_id,notes)
  values(new.learner_id,new.competency_id,'teacher_observation',new.score,1.5,true,new.educator_id,'educator_observations',new.id,new.notes);
 end if;
 return new;
end;$$;
revoke all on function private.trg_observation_to_mastery() from public,anon,authenticated;
drop trigger if exists trg_observation_to_mastery on public.educator_observations;
create trigger trg_observation_to_mastery after insert on public.educator_observations for each row execute function private.trg_observation_to_mastery();

insert into public.learning_competencies(competency_key,stage_key,domain_key,domain_title,title,description,display_order,target_score,content_status) values
('s16_literacy','school_1_6','literacy','Literacy & Communication','Read, understand and communicate','Build age-appropriate reading comprehension, vocabulary, speaking and writing.',10,80,'educator_review'),
('s16_numeracy','school_1_6','numeracy','Numeracy & Logic','Number sense and mathematical reasoning','Use numbers, operations, patterns and simple reasoning to solve everyday problems.',20,80,'educator_review'),
('s16_science','school_1_6','science','Science & Discovery','Observe, ask and investigate','Use observation, questions and simple evidence to understand the natural world.',30,80,'educator_review'),
('s16_digital','school_1_6','digital','Digital & AI Foundations','Safe digital and AI awareness','Use digital tools safely and understand basic ideas about computers and AI.',40,80,'educator_review'),
('s16_creativity','school_1_6','creativity','Creativity & Making','Create, design and explain','Turn ideas into drawings, models, stories or simple projects and explain choices.',50,80,'educator_review'),
('s16_learning','school_1_6','learning','Learning Habits','Plan, persist and reflect','Build focus, persistence, curiosity and simple reflection on learning.',60,80,'educator_review'),
('s78_literacy','school_7_8','literacy','Communication & Research','Read, research and communicate','Understand increasingly complex texts, find information and communicate clearly.',10,80,'educator_review'),
('s78_math','school_7_8','numeracy','Mathematics & Logic','Reason with mathematics','Use fractions, ratios, algebraic thinking, data and logic to solve problems.',20,80,'educator_review'),
('s78_stem','school_7_8','science','STEM Foundations','Investigate scientific questions','Use evidence, measurement and simple experiments to explain scientific ideas.',30,80,'educator_review'),
('s78_digital','school_7_8','digital','Digital & Coding','Use digital tools and computational thinking','Practice online safety, digital creation and introductory coding/computational thinking.',40,80,'educator_review'),
('s78_ai','school_7_8','ai','AI Literacy','Understand responsible AI use','Recognize what AI can and cannot do and use AI responsibly for learning.',50,80,'educator_review'),
('s78_explore','school_7_8','future','Future Exploration','Explore interests and strengths','Connect subjects, interests and strengths to broad future learning possibilities.',60,75,'educator_review'),
('s910_academic','school_9_10','academic','Academic Skills','Analyze, research and communicate','Use evidence, structured writing, research and presentation skills across subjects.',10,80,'educator_review'),
('s910_stem','school_9_10','stem','STEM & Problem Solving','Apply STEM reasoning','Use mathematics, science and data to solve multi-step problems and explain reasoning.',20,80,'educator_review'),
('s910_digital','school_9_10','digital','Digital, Coding & Data','Build with digital tools','Use coding, data and digital creation tools to solve problems and build projects.',30,80,'educator_review'),
('s910_ai','school_9_10','ai','AI & Information Literacy','Use AI critically and responsibly','Evaluate AI output, verify information and use AI as a learning/building tool responsibly.',40,80,'educator_review'),
('s910_projects','school_9_10','projects','Projects & Teamwork','Plan and deliver projects','Define a problem, plan work, collaborate, create an output and reflect on results.',50,80,'educator_review'),
('s910_pathways','school_9_10','future','Pathway Exploration','Compare education and career directions','Explore subject pathways, TVET, university and career families without premature tracking.',60,75,'educator_review'),
('s1112_academic','school_11_12','academic','Academic & Research Skills','Prepare for post-secondary study','Research, reason, communicate and manage advanced school-level learning tasks.',10,80,'educator_review'),
('s1112_digital','school_11_12','digital','Digital & AI Capability','Use digital and AI tools productively','Use data, digital tools and AI critically for study, projects and transition planning.',20,80,'educator_review'),
('s1112_projects','school_11_12','projects','Projects & Evidence','Build portfolio-quality evidence','Complete meaningful projects that demonstrate applied knowledge and transferable skills.',30,80,'educator_review'),
('s1112_transition','school_11_12','transition','Transition Readiness','Plan the next education step','Compare university, College/TVET, scholarship and other post-school pathways.',40,80,'educator_review'),
('s1112_career','school_11_12','career','Career Exploration','Understand fields and skill requirements','Explore career families, required skills and realistic routes without promising outcomes.',50,75,'educator_review'),
('s1112_life','school_11_12','life','Life & Financial Literacy','Make informed life and financial decisions','Build practical financial, decision-making and self-management capability for transition.',60,80,'educator_review'),
('tvet_technical','college_tvet','technical','Technical Competence','Demonstrate occupational competence','Apply practical and technical skills to realistic tasks in the learner’s field.',10,85,'framework'),
('tvet_safety','college_tvet','safety','Safety & Quality','Work safely and to quality standards','Follow safety, quality, process and documentation expectations in practical work.',20,85,'framework'),
('tvet_digital','college_tvet','digital','Digital Workplace Skills','Use digital tools for technical work','Use relevant digital tools, documentation, data and AI responsibly in technical contexts.',30,80,'framework'),
('tvet_problem','college_tvet','problem_solving','Applied Problem Solving','Diagnose and solve practical problems','Identify causes, test options and document practical solutions.',40,85,'framework'),
('tvet_work','college_tvet','work_readiness','Work Readiness','Communicate and deliver professionally','Demonstrate reliability, communication, teamwork and professional practice.',50,80,'framework'),
('tvet_growth','college_tvet','growth','Career Growth','Plan certification and progression','Identify next credentials, placements, specialization or entrepreneurship steps.',60,75,'framework'),
('uni_academic','university','academic','Academic & Research Capability','Research, analyze and communicate','Use disciplined research, evidence, reasoning and communication appropriate to higher education.',10,85,'framework'),
('uni_domain','university','domain','Disciplinary Capability','Apply field-specific knowledge','Demonstrate increasingly advanced capability in the learner’s chosen field.',20,85,'framework'),
('uni_digital','university','digital','Digital, Data & AI','Use advanced digital tools responsibly','Apply data, software and AI tools with verification, ethics and domain judgment.',30,85,'framework'),
('uni_projects','university','projects','Projects & Portfolio','Create real evidence of capability','Build projects, research, case work or prototypes that demonstrate applied skill.',40,85,'framework'),
('uni_professional','university','professional','Professional Readiness','Work with professional standards','Communicate, collaborate, manage work and understand professional expectations.',50,80,'framework'),
('uni_transition','university','transition','Career & Further Study Navigation','Plan the next opportunity','Connect verified capability to internships, employment, entrepreneurship or further study.',60,80,'framework')
on conflict(competency_key) do update set title=excluded.title,description=excluded.description,domain_title=excluded.domain_title,display_order=excluded.display_order,target_score=excluded.target_score,content_status=excluded.content_status,updated_at=now();

insert into public.opportunity_graph_nodes(node_key,node_type,stage_key,title,description,route_key,metadata)
select 'stage:'||stage_key,'education_stage',stage_key,title,coalesce(subtitle,title),'home',jsonb_build_object('audience_group',audience_group,'order',display_order) from public.education_audience_stages
on conflict(node_key) do update set title=excluded.title,description=excluded.description,metadata=excluded.metadata,active=true;

insert into public.opportunity_graph_nodes(node_key,node_type,career_path_id,title,description,route_key,metadata)
select 'career:'||id::text,'career_path',id,title,description,'academy',jsonb_build_object('category',category,'badge',badge_title) from public.career_paths
on conflict(node_key) do update set title=excluded.title,description=excluded.description,metadata=excluded.metadata,active=true;

insert into public.opportunity_graph_nodes(node_key,node_type,title,description,route_key,metadata) values
('destination:scholarships','destination','Scholarships','Find verified scholarship opportunities and prepare eligibility evidence.','scholarships','{}'),
('destination:college_tvet','destination','College / TVET','Practical and technical post-secondary pathways.','mela-next','{}'),
('destination:university','destination','University','Higher-education pathways and fields of study.','mela-next','{}'),
('destination:employment','destination','Employment & Internships','Verified work opportunities matched to evidence and stage eligibility.','opportunities','{}'),
('destination:entrepreneurship','destination','Entrepreneurship','Build projects, business capability and responsible earning pathways.','mela-next','{}')
on conflict(node_key) do update set title=excluded.title,description=excluded.description,route_key=excluded.route_key,active=true;

with pairs(f,t,r,w,why) as (values
 ('stage:school_1_6','stage:school_7_8','progresses_to',1.0,'Build foundations before intermediate exploration.'),
 ('stage:school_7_8','stage:school_9_10','progresses_to',1.0,'Strengthen subjects and begin pathway exploration.'),
 ('stage:school_9_10','stage:school_11_12','progresses_to',1.0,'Prepare for senior-secondary transition choices.'),
 ('stage:school_11_12','destination:college_tvet','opens',1.0,'Practical and technical post-secondary option.'),
 ('stage:school_11_12','destination:university','opens',1.0,'Higher-education option.'),
 ('stage:school_11_12','destination:scholarships','opens',1.0,'Scholarship search and readiness.'),
 ('stage:college_tvet','destination:employment','can_lead_to',1.0,'Verified technical capability can connect to placements and work.'),
 ('stage:college_tvet','destination:entrepreneurship','can_lead_to',0.8,'Practical skills can support responsible entrepreneurship.'),
 ('stage:university','destination:employment','can_lead_to',1.0,'Verified academic and project evidence can connect to work.'),
 ('stage:university','destination:entrepreneurship','can_lead_to',0.8,'Projects and professional skills can support entrepreneurship.')
)
insert into public.opportunity_graph_edges(from_node_id,to_node_id,relationship,weight,rationale)
select f.id,t.id,p.r,p.w,p.why from pairs p join public.opportunity_graph_nodes f on f.node_key=p.f join public.opportunity_graph_nodes t on t.node_key=p.t
on conflict(from_node_id,to_node_id,relationship) do update set weight=excluded.weight,rationale=excluded.rationale,active=true;

insert into public.opportunity_graph_edges(from_node_id,to_node_id,relationship,weight,rationale)
select s.id,c.id,'specializes_into',0.9,'Explore a Mela career pathway and build evidence before making high-stakes choices.'
from public.opportunity_graph_nodes s cross join public.opportunity_graph_nodes c
where s.node_key in ('stage:school_11_12','stage:college_tvet','stage:university') and c.node_type='career_path'
on conflict(from_node_id,to_node_id,relationship) do nothing;

insert into public.opportunity_graph_edges(from_node_id,to_node_id,relationship,weight,rationale)
select c.id,d.id,'can_lead_to',1.0,'Verified pathway skills can support matching to real opportunities.'
from public.opportunity_graph_nodes c join public.opportunity_graph_nodes d on d.node_key='destination:employment'
where c.node_type='career_path'
on conflict(from_node_id,to_node_id,relationship) do nothing;

insert into public.platform_audience_subsections(subsection_key,section_key,title,description,route_key,target_stages,target_partner_types,display_order,active) values
('school_mastery','school_prove','My Mastery Map','See what is mastered, developing and next to learn.','mastery',array['school_1_6','school_7_8','school_9_10','school_11_12'],array[]::text[],5,true),
('school_passport_v2','school_prove','Learner Passport','A growing record of mastery, projects and verified progress.','passport',array['school_1_6','school_7_8','school_9_10','school_11_12'],array[]::text[],6,true),
('school_opportunity_graph','school_explore','My Future Map','See how today’s learning can connect to future education pathways.','opportunity-graph',array['school_7_8','school_9_10','school_11_12'],array[]::text[],25,true),
('school_mela_next','school_transition','Mela Next','Build a personalized transition plan for the next education step.','mela-next',array['school_9_10','school_11_12'],array[]::text[],5,true),
('higher_mastery','higher_prove','My Mastery Map','Evidence-weighted capability across learning and professional domains.','mastery',array['college_tvet','university'],array[]::text[],5,true),
('higher_passport_v2','higher_prove','Learner & Career Passport','Mastery, projects, verified skills and professional evidence in one record.','passport',array['college_tvet','university'],array[]::text[],6,true),
('higher_graph','higher_opportunities','Opportunity Graph','Connect skills, pathways and verified opportunities.','opportunity-graph',array['college_tvet','university'],array[]::text[],5,true),
('higher_next','higher_network','Mela Next','Plan the next credential, placement, job, further study or entrepreneurship step.','mela-next',array['college_tvet','university'],array[]::text[],5,true),
('partner_teacher_copilot','partner_learning','Teacher Copilot & Classrooms','Verified educators create classrooms, see mastery gaps and plan interventions.','teacher-copilot',array[]::text[],array['school','college_tvet','university','training_mentor'],5,true)
on conflict(subsection_key) do update set title=excluded.title,description=excluded.description,route_key=excluded.route_key,target_stages=excluded.target_stages,target_partner_types=excluded.target_partner_types,display_order=excluded.display_order,active=true;

grant select on public.learning_competencies,public.opportunity_graph_nodes,public.opportunity_graph_edges to authenticated;
grant select on public.learner_mastery_records,public.learner_mastery_evidence,public.educator_profiles,public.educator_classrooms,public.educator_classroom_members,public.educator_observations to authenticated;
grant select,insert,update,delete on public.learner_projects,public.learner_project_competencies,public.mela_transition_plans,public.mela_transition_steps to authenticated;
grant select,insert,update,delete on all tables in schema public to service_role;

;
