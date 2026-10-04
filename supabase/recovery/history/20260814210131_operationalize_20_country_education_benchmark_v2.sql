-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260814210131
create table public.education_benchmark_practices (
  practice_key text primary key,
  country_code text not null references public.education_benchmark_systems(country_code) on update cascade on delete restrict,
  engine_key text not null references public.mela_education_engines(engine_key) on update cascade on delete restrict,
  title text not null,
  source_principle text not null,
  mela_adaptation text not null,
  stage_keys text[] not null default '{}'::text[],
  priority smallint not null default 3 check (priority between 1 and 5),
  target_outcome text not null,
  evidence_basis text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index education_benchmark_practices_country_idx on public.education_benchmark_practices(country_code);
create index education_benchmark_practices_engine_idx on public.education_benchmark_practices(engine_key);
create index education_benchmark_practices_stage_gin on public.education_benchmark_practices using gin(stage_keys);
alter table public.education_benchmark_practices enable row level security;
create policy education_benchmark_practices_read on public.education_benchmark_practices for select to authenticated using (active or private.is_admin_user());
create policy education_benchmark_practices_admin_write on public.education_benchmark_practices for all to authenticated using (private.is_admin_user()) with check (private.is_admin_user());
grant select on public.education_benchmark_practices to authenticated;
grant all on public.education_benchmark_practices to service_role;

insert into public.education_benchmark_practices
(practice_key,country_code,engine_key,title,source_principle,mela_adaptation,stage_keys,priority,target_outcome,evidence_basis)
values
('sg_mastery_progressions','SG','mastery','Mastery before acceleration','Coherent curriculum, strong fundamentals and explicit progression','Use competency progressions, diagnostic evidence and re-teaching before acceleration instead of course-completion as the main success signal',array['school_1_6','school_7_8','school_9_10','school_11_12'],1,'Higher foundational mastery with fewer hidden gaps','OECD PISA and Singapore curriculum/teacher-development practice'),
('ee_digital_by_design','EE','teacher_copilot','Digital-by-design teaching','Digital competence is integrated with normal teaching and school capability','Make digital and AI literacy cross-curricular while giving teachers planning, differentiation and evidence tools',array['school_1_6','school_7_8','school_9_10','school_11_12','college_tvet','university'],2,'Digital competence without replacing teachers','OECD PISA and Estonia digital-education policy'),
('fi_early_support','FI','diagnostic_catchup','Support before failure','Early support and learner wellbeing reduce the need to wait for major failure','Trigger short catch-up plans from diagnostic/mastery evidence and escalate support before repeated failure',array['school_1_6','school_7_8','school_9_10','school_11_12'],1,'Earlier intervention and lower persistent learning gaps','Finnish national core curriculum and OECD system evidence'),
('jp_lesson_study','JP','teacher_copilot','Collaborative teacher improvement','Teachers improve instruction through structured peer learning and lesson reflection','Add teacher observation, lesson reflection and reusable high-quality lesson patterns to Mela Teacher Copilot',array['school_1_6','school_7_8','school_9_10','school_11_12'],2,'Continuous improvement in teaching quality','Japan lesson-study practice and OECD system evidence'),
('kr_high_expectations_transition','KR','mela_next','High expectations with transition planning','Strong academic expectations and high progression aspirations are paired with structured pathways','Show clear mastery targets and personalized next-step routes while protecting wellbeing and avoiding pressure-only design',array['school_9_10','school_11_12','college_tvet','university'],2,'Higher readiness for the next education or career stage','OECD PISA and Korean education transition practice'),
('ca_inclusive_pathways','CA','passport','Inclusive portable learner evidence','Strong systems support diverse learners while maintaining visible learning outcomes','Make the Learner Passport multilingual, evidence-based and portable across school, TVET, university and work transitions',array['school_1_6','school_7_8','school_9_10','school_11_12','college_tvet','university'],2,'Continuity and inclusion across learner transitions','OECD PISA and provincial competency-based approaches'),
('au_general_capabilities','AU','institution_outcomes','Capabilities across the curriculum','General capabilities such as literacy, numeracy, critical thinking and digital literacy are developed across subjects','Measure Mela competencies across learning experiences and give institutions outcome dashboards instead of activity-only dashboards',array['school_1_6','school_7_8','school_9_10','school_11_12'],2,'Visible cross-curricular capability growth','Australian Curriculum general capabilities'),
('nz_local_project_learning','NZ','projects_impact','Learner agency through local-context projects','Local curriculum flexibility and learner agency can make learning relevant','Use Ethiopian community, agriculture, health, climate, enterprise and technology problems as project evidence in the Passport',array['school_1_6','school_7_8','school_9_10','school_11_12'],2,'More authentic problem solving and learner ownership','New Zealand curriculum and key competency practice'),
('ie_literacy_fundamentals','IE','mastery','Sustained focus on literacy fundamentals','Strong literacy outcomes rely on clear expectations and sustained attention to core learning','Give literacy and communication persistent mastery visibility across stages and languages',array['school_1_6','school_7_8','school_9_10','school_11_12'],1,'Strong multilingual literacy foundations','OECD PISA and Irish curriculum/assessment practice'),
('ch_dual_vet','CH','opportunity_graph','Education connected to real work','Vocational pathways combine learning with meaningful employer participation','Connect TVET and upper-secondary competencies to verified employer projects, apprenticeships and work-based evidence',array['school_11_12','college_tvet','university'],1,'Stronger school-to-work transition','Swiss vocational education and training system'),
('nl_pathway_transparency','NL','mela_next','Multiple transparent pathways','Learners can see distinct academic and vocational routes and their progression requirements','Build visual pathway maps that show requirements, alternatives and bridge routes without permanently locking learners into one track',array['school_9_10','school_11_12','college_tvet'],2,'Fewer dead ends and better-informed choices','Dutch secondary and vocational pathway structure'),
('dk_collaborative_projects','DK','projects_impact','Collaboration and project learning','Broad education and collaborative learning support agency and problem solving','Score teamwork, communication and reflection alongside technical project outcomes in Arena and projects',array['school_7_8','school_9_10','school_11_12','college_tvet','university'],3,'Stronger collaboration and applied capability','Danish broad-education and project-learning practice'),
('pt_belonging_recovery','PT','family_support','Belonging and support as learning conditions','Learning improvement is strengthened by inclusion, belonging and reduced reliance on repetition','Give families simple progress/support signals and measure belonging/support without surveillance',array['school_1_6','school_7_8','school_9_10','school_11_12'],3,'Higher engagement and earlier support','Portugal improvement and inclusion experience'),
('pl_clear_standards','PL','mastery','Clear standards with support','Clear core expectations can support system improvement when paired with stable support','Keep stage competencies explicit and use mastery evidence to trigger support rather than relying on grade level alone',array['school_1_6','school_7_8','school_9_10','school_11_12'],2,'Clearer learning expectations and progression','OECD PISA and Poland curriculum reform experience'),
('vn_level_appropriate_learning','VN','diagnostic_catchup','Teach at the learner actual level','Strong fundamentals are supported by clear curriculum, materials, attendance and frequent classroom assessment','Use diagnostics to assign level-appropriate practice and short recovery sequences, especially in literacy, numeracy and science',array['school_1_6','school_7_8','school_9_10'],1,'Faster recovery of foundational skills','World Bank and Vietnam education system evidence'),
('cz_academic_technical_balance','CZ','mela_next','Academic foundations plus technical routes','Technical pathways can coexist with strong mathematics and science foundations','Keep core mastery visible while offering technical exploration and later TVET/employment routes',array['school_9_10','school_11_12','college_tvet'],3,'Respected technical routes with strong fundamentals','OECD education and VET evidence'),
('si_balanced_routes','SI','mela_next','Balanced academic and technical capability','A broad core curriculum can coexist with strong technical education','Use common Mela competencies across academic and technical routes so learners can move between pathways more easily',array['school_9_10','school_11_12','college_tvet'],3,'More flexible progression between academic and technical routes','OECD education and VET evidence'),
('se_digital_citizenship','SE','teacher_copilot','Digital citizenship with learner agency','Digital learning requires agency, inclusion and responsible use rather than device exposure alone','Embed AI safety, source evaluation, attention management and digital citizenship into teacher-guided learning',array['school_7_8','school_9_10','school_11_12'],3,'Safer and more responsible digital learning','Swedish digital-education and OECD evidence'),
('lt_resilient_digital_system','LT','institution_outcomes','Measure resilience during system change','Digital transformation works better when access, teacher support and outcomes are monitored together','Track institution-level mastery, intervention, language and access gaps so Mela can distinguish technology usage from actual learning impact',array['school_1_6','school_7_8','school_9_10','school_11_12','college_tvet','university'],3,'Evidence-based digital transformation','Lithuania education reform and digital transformation evidence'),
('uy_equitable_digital_access','UY','mela_lite','Universal access needs pedagogy and continuity','Large-scale digital inclusion pairs access infrastructure with a national learning platform and teacher support','Build downloadable multilingual packs, low-bandwidth flows and sync recovery so intermittent connectivity does not break learning',array['school_1_6','school_7_8','school_9_10','school_11_12','college_tvet','university'],1,'Reduced connectivity-driven learning exclusion','Plan Ceibal and Uruguay digital inclusion experience');

create table public.mela_outcome_metrics (
  metric_key text primary key,
  engine_key text not null references public.mela_education_engines(engine_key) on update cascade on delete restrict,
  title text not null,
  description text not null,
  unit text not null,
  direction text not null check (direction in ('higher_better','lower_better','target_band')),
  target_value numeric,
  stage_keys text[] not null default '{}'::text[],
  privacy_level text not null default 'system' check (privacy_level in ('learner','institution','system')),
  privacy_threshold integer not null default 10 check (privacy_threshold >= 1),
  calculation_notes text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index mela_outcome_metrics_engine_idx on public.mela_outcome_metrics(engine_key);
create index mela_outcome_metrics_stage_gin on public.mela_outcome_metrics using gin(stage_keys);
alter table public.mela_outcome_metrics enable row level security;
create policy mela_outcome_metrics_read on public.mela_outcome_metrics for select to authenticated using (active or private.is_admin_user());
create policy mela_outcome_metrics_admin_write on public.mela_outcome_metrics for all to authenticated using (private.is_admin_user()) with check (private.is_admin_user());
grant select on public.mela_outcome_metrics to authenticated;
grant all on public.mela_outcome_metrics to service_role;

insert into public.mela_outcome_metrics
(metric_key,engine_key,title,description,unit,direction,stage_keys,privacy_level,privacy_threshold,calculation_notes)
values
('mastery_growth_90d','mastery','90-day mastery growth','Average change in competency mastery for learners with evidence in both periods','percentage_points','higher_better',array['school_1_6','school_7_8','school_9_10','school_11_12','college_tvet','university'],'institution',10,'Compare like-for-like competency evidence; do not count course views as mastery.'),
('foundational_gap_rate','diagnostic_catchup','Foundational gap rate','Share of learners below the agreed foundational threshold for their current stage','percent','lower_better',array['school_1_6','school_7_8','school_9_10'],'institution',10,'Use diagnostics and verified mastery evidence; separate by domain.'),
('catchup_completion_rate','diagnostic_catchup','Catch-up completion rate','Share of activated catch-up plans completed with target evidence','percent','higher_better',array['school_1_6','school_7_8','school_9_10','school_11_12'],'institution',10,'Completion should require evidence improvement, not only item clicks.'),
('verified_passport_evidence_ratio','passport','Verified Passport evidence ratio','Share of Passport evidence that is independently verified or assessment-backed','percent','higher_better',array['school_7_8','school_9_10','school_11_12','college_tvet','university'],'learner',1,'Keep self-declared evidence visible but distinct from verified evidence.'),
('verified_project_rate','projects_impact','Verified project rate','Share of submitted learner projects reviewed and verified against a rubric','percent','higher_better',array['school_1_6','school_7_8','school_9_10','school_11_12','college_tvet','university'],'institution',10,'Include age-appropriate project rubrics and reviewer provenance.'),
('transition_plan_completion_rate','mela_next','Transition plan completion','Share of transition-stage learners with an active plan and completed next-step actions','percent','higher_better',array['school_9_10','school_11_12','college_tvet','university'],'institution',10,'Measure progress through actions, not whether a learner selected a career label.'),
('opportunity_conversion_rate','opportunity_graph','Opportunity conversion rate','Share of eligible opportunity engagements that progress to application, interview, placement or award','percent','higher_better',array['school_11_12','college_tvet','university'],'institution',10,'Respect stage and age gates; school learners should not be evaluated on adult work outcomes.'),
('teacher_intervention_response_hours','teacher_copilot','Teacher intervention response time','Median time between a high-confidence learning support signal and an educator action','hours','lower_better',array['school_1_6','school_7_8','school_9_10','school_11_12'],'institution',10,'Use for workflow improvement, not punitive teacher surveillance.'),
('family_engagement_rate','family_support','Family support engagement','Share of eligible guardian relationships receiving and engaging with useful progress/support summaries','percent','higher_better',array['school_1_6','school_7_8','school_9_10','school_11_12'],'institution',10,'Measure useful support interactions rather than constant monitoring.'),
('institution_gap_closure_rate','institution_outcomes','Learning gap closure','Change in high-priority mastery gaps across an institution over a reporting period','percentage_points','higher_better',array['school_1_6','school_7_8','school_9_10','school_11_12','college_tvet','university'],'institution',10,'Report only sufficiently large cohorts and show uncertainty for small samples.'),
('offline_sync_success_rate','mela_lite','Offline sync success','Share of offline learning sync attempts completed without data loss or unresolved conflict','percent','higher_better',array['school_1_6','school_7_8','school_9_10','school_11_12','college_tvet','university'],'system',10,'Track reliability by app version and connectivity class without exposing learner identity.'),
('language_equity_gap','institution_outcomes','Language learning-equity gap','Difference in learning outcome rates across supported interface/content languages after controlling for stage','percentage_points','lower_better',array['school_1_6','school_7_8','school_9_10','school_11_12','college_tvet','university'],'system',30,'Use aggregate analysis only; never rank individual learners by language background.');

create table public.mela_offline_content_packs (
  id uuid primary key default gen_random_uuid(),
  pack_key text not null unique,
  stage_key text not null references public.education_audience_stages(stage_key) on update cascade on delete restrict,
  language_code text not null references public.platform_languages(language_code) on update cascade on delete restrict,
  title text not null,
  description text,
  content_version integer not null default 1 check (content_version >= 1),
  estimated_bytes bigint check (estimated_bytes is null or estimated_bytes >= 0),
  manifest jsonb not null default '{}'::jsonb,
  checksum text,
  published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index mela_offline_content_packs_stage_lang_idx on public.mela_offline_content_packs(stage_key,language_code,published);
alter table public.mela_offline_content_packs enable row level security;
create policy mela_offline_content_packs_read on public.mela_offline_content_packs for select to authenticated using (published or private.is_admin_user());
create policy mela_offline_content_packs_admin_write on public.mela_offline_content_packs for all to authenticated using (private.is_admin_user()) with check (private.is_admin_user());
grant select on public.mela_offline_content_packs to authenticated;
grant all on public.mela_offline_content_packs to service_role;

create table public.learner_offline_sync_state (
  user_id uuid not null references auth.users(id) on delete cascade,
  pack_id uuid not null references public.mela_offline_content_packs(id) on delete cascade,
  downloaded_version integer check (downloaded_version is null or downloaded_version >= 1),
  downloaded_at timestamptz,
  last_sync_at timestamptz,
  pending_event_count integer not null default 0 check (pending_event_count >= 0),
  last_error_code text,
  client_state jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key(user_id,pack_id)
);
create index learner_offline_sync_state_user_idx on public.learner_offline_sync_state(user_id,updated_at desc);
alter table public.learner_offline_sync_state enable row level security;
create policy learner_offline_sync_state_self on public.learner_offline_sync_state for all to authenticated using ((select auth.uid())=user_id or private.is_admin_user()) with check ((select auth.uid())=user_id or private.is_admin_user());
grant select,insert,update,delete on public.learner_offline_sync_state to authenticated;
grant all on public.learner_offline_sync_state to service_role;

create or replace function public.get_mela_education_blueprint()
returns jsonb language sql stable set search_path=''
as $$
select jsonb_build_object(
  'version','2026.08-benchmark-v1',
  'benchmark_country_count',(select count(*) from public.education_benchmark_systems where active),
  'benchmark_practice_count',(select count(*) from public.education_benchmark_practices where active),
  'stages',coalesce((select jsonb_agg(to_jsonb(s) order by s.display_order) from public.education_audience_stages s),'[]'::jsonb),
  'languages',coalesce((select jsonb_agg(jsonb_build_object('code',l.language_code,'name',l.language_name,'native_name',l.native_name,'enabled',l.enabled) order by l.sort_order) from public.platform_languages l where l.enabled),'[]'::jsonb),
  'engines',coalesce((select jsonb_agg(to_jsonb(e) order by e.display_order) from public.mela_education_engines e),'[]'::jsonb),
  'benchmarks',coalesce((select jsonb_agg(to_jsonb(b) order by b.country_name) from public.education_benchmark_systems b where b.active),'[]'::jsonb),
  'practices',coalesce((select jsonb_agg(to_jsonb(p) order by p.priority,p.country_code) from public.education_benchmark_practices p where p.active),'[]'::jsonb),
  'outcome_metrics',coalesce((select jsonb_agg(to_jsonb(m) order by m.engine_key,m.metric_key) from public.mela_outcome_metrics m where m.active),'[]'::jsonb)
);
$$;
revoke all on function public.get_mela_education_blueprint() from public;
grant execute on function public.get_mela_education_blueprint() to authenticated,service_role;

create or replace function public.get_my_learning_home_v3()
returns jsonb language plpgsql stable set search_path=''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_profile public.profiles%rowtype;
  v_stage public.education_audience_stages%rowtype;
  v_mastery jsonb;
  v_passport jsonb;
  v_graph jsonb := null;
  v_catchup jsonb := null;
  v_focus text;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select * into v_profile from public.profiles where id=v_uid;
  if not found then raise exception 'profile not found'; end if;
  select * into v_stage from public.education_audience_stages where stage_key=v_profile.education_stage_key;
  v_mastery := public.get_my_mastery_engine();
  v_passport := public.get_my_learner_passport_v2();
  if v_profile.education_stage_key in ('school_11_12','college_tvet','university') then v_graph := public.get_my_opportunity_graph(); end if;

  select jsonb_build_object(
    'id',p.id,'title',p.title,'rationale',p.rationale,'duration_weeks',p.duration_weeks,'status',p.status,
    'items',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'competency_id',i.competency_id,'week_number',i.week_number,'priority',i.priority,'target_score',i.target_score,'status',i.status,'notes',i.notes) order by i.week_number,i.priority) from public.learner_catchup_plan_items i where i.plan_id=p.id),'[]'::jsonb)
  ) into v_catchup
  from public.learner_catchup_plans p
  where p.user_id=v_uid and p.status='active'
  order by p.created_at desc limit 1;

  v_focus := case
    when not coalesce(v_profile.education_onboarding_completed,false) then 'complete_education_onboarding'
    when v_catchup is not null then 'continue_catchup_plan'
    when coalesce((v_mastery->>'overall_score')::numeric,0) < 70 then 'strengthen_mastery'
    when v_profile.education_stage_key in ('school_9_10','school_11_12','college_tvet','university') then 'build_transition_evidence'
    else 'apply_learning_in_projects'
  end;

  return jsonb_build_object(
    'generated_at',now(),
    'profile',jsonb_build_object('id',v_profile.id,'full_name',v_profile.full_name,'stage_key',v_profile.education_stage_key,'grade_level',v_profile.grade_level,'institution_name',v_profile.institution_name,'preferred_language',coalesce(v_profile.preferred_language,'en')),
    'stage',case when v_stage.stage_key is null then null else to_jsonb(v_stage) end,
    'recommended_focus',v_focus,
    'feature_access',coalesce((select jsonb_object_agg(f.feature_key,jsonb_build_object('mode',f.access_mode,'rationale',f.rationale)) from public.audience_feature_matrix f where f.stage_key=v_profile.education_stage_key),'{}'::jsonb),
    'mastery',v_mastery,
    'passport',v_passport,
    'catchup_plan',v_catchup,
    'opportunity_graph',v_graph,
    'benchmark_principles',coalesce((select jsonb_agg(jsonb_build_object('practice_key',x.practice_key,'country',b.country_name,'title',x.title,'mela_adaptation',x.mela_adaptation,'target_outcome',x.target_outcome,'engine_key',x.engine_key) order by x.priority,x.country_code) from public.education_benchmark_practices x join public.education_benchmark_systems b on b.country_code=x.country_code where x.active and v_profile.education_stage_key=any(x.stage_keys)),'[]'::jsonb),
    'offline',jsonb_build_object('published_pack_count',(select count(*) from public.mela_offline_content_packs p where p.published and p.stage_key=v_profile.education_stage_key and p.language_code=coalesce(v_profile.preferred_language,'en')),'sync_records',(select count(*) from public.learner_offline_sync_state s where s.user_id=v_uid))
  );
end;
$$;
revoke all on function public.get_my_learning_home_v3() from public;
grant execute on function public.get_my_learning_home_v3() to authenticated,service_role;

create or replace function public.admin_education_system_snapshot()
returns jsonb language plpgsql stable set search_path=''
as $$
begin
  if not private.is_admin_user() then raise exception 'admin access required'; end if;
  return jsonb_build_object(
    'generated_at',now(),
    'benchmark',jsonb_build_object(
      'countries',(select count(*) from public.education_benchmark_systems where active),
      'practices',(select count(*) from public.education_benchmark_practices where active),
      'engines',(select jsonb_object_agg(implementation_status,cnt) from (select implementation_status,count(*) cnt from public.mela_education_engines group by implementation_status)s)
    ),
    'learners',jsonb_build_object(
      'with_stage',(select count(*) from public.profiles where education_stage_key is not null),
      'by_stage',(select coalesce(jsonb_object_agg(education_stage_key,cnt),'{}'::jsonb) from (select education_stage_key,count(*) cnt from public.profiles where education_stage_key is not null group by education_stage_key)s),
      'mastery_records',(select count(*) from public.learner_mastery_records),
      'active_catchup_plans',(select count(*) from public.learner_catchup_plans where status='active'),
      'projects',(select count(*) from public.learner_projects),
      'verified_projects',(select count(*) from public.learner_projects where verified)
    ),
    'educators',jsonb_build_object(
      'profiles',(select count(*) from public.educator_profiles),
      'classrooms',(select count(*) from public.educator_classrooms),
      'copilot_requests',(select count(*) from public.educator_copilot_requests)
    ),
    'institutions',jsonb_build_object(
      'education_partners',(select count(*) from public.sector_partner_organizations where partner_type_key in ('school','college_tvet','university')),
      'outcome_snapshots',(select count(*) from public.institution_outcome_snapshots),
      'defined_metrics',(select count(*) from public.mela_outcome_metrics where active)
    ),
    'offline',jsonb_build_object(
      'published_packs',(select count(*) from public.mela_offline_content_packs where published),
      'sync_states',(select count(*) from public.learner_offline_sync_state)
    )
  );
end;
$$;
revoke all on function public.admin_education_system_snapshot() from public;
grant execute on function public.admin_education_system_snapshot() to authenticated,service_role;

update public.mela_education_engines set current_assets=jsonb_build_object('rpc','get_my_learner_passport_v2','existing','Career Passport, mastery evidence, verified skills and projects','benchmark_practices','education_benchmark_practices'),updated_at=now() where engine_key='passport';
update public.mela_education_engines set current_assets=jsonb_build_object('tables',jsonb_build_array('learner_diagnostic_sessions','learner_diagnostic_results','learner_catchup_plans','learner_catchup_plan_items'),'uses','learning_competencies and mastery evidence','benchmark_practices','education_benchmark_practices'),updated_at=now() where engine_key='diagnostic_catchup';
update public.mela_education_engines set current_assets=jsonb_build_object('tables',jsonb_build_array('educator_profiles','educator_classrooms','educator_observations','educator_copilot_requests'),'principle','teacher-in-the-loop; never teacher replacement','benchmark_practices','education_benchmark_practices'),updated_at=now() where engine_key='teacher_copilot';
update public.mela_education_engines set current_assets=jsonb_build_object('tables',jsonb_build_array('learner_projects','learner_project_competencies'),'existing','Sponsored Challenges and Arena can supply authentic projects','benchmark_practices','education_benchmark_practices'),updated_at=now() where engine_key='projects_impact';
update public.mela_education_engines set current_assets=jsonb_build_object('tables',jsonb_build_array('guardian_relationships'),'next','family progress summaries and offline support activities','benchmark_practices','education_benchmark_practices'),updated_at=now() where engine_key='family_support';
update public.mela_education_engines set implementation_status='partial',current_assets=jsonb_build_object('tables',jsonb_build_array('mela_outcome_metrics','institution_outcome_snapshots'),'admin_rpc','admin_education_system_snapshot','principle','measure mastery and progression, not video views'),updated_at=now() where engine_key='institution_outcomes';
update public.mela_education_engines set implementation_status='foundation',current_assets=jsonb_build_object('tables',jsonb_build_array('mela_offline_content_packs','learner_offline_sync_state'),'next','publish translated downloadable packs and connect client offline event queue','benchmark_practices','education_benchmark_practices'),updated_at=now() where engine_key='mela_lite';
;
