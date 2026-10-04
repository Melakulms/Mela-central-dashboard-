-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815045656
-- Mela Education Value OS v7: Ethiopia curriculum bridge + local impact validation.
-- This migration intentionally labels curriculum mappings and benchmark practices as unvalidated/framework
-- until Ethiopian educator/curriculum review and real pilot evidence support stronger claims.

create table if not exists public.mela_curriculum_alignments (
  id uuid primary key default gen_random_uuid(),
  competency_id uuid not null references public.learning_competencies(id) on delete cascade,
  curriculum_system text not null default 'Ethiopia',
  stage_key text not null references public.education_audience_stages(stage_key) on delete cascade,
  subject_key text not null,
  subject_title text not null,
  strand_title text,
  local_contexts text[] not null default '{}',
  alignment_note text not null,
  source_reference text,
  review_status text not null default 'framework' check (review_status in ('framework','educator_review','curriculum_review','approved','retired')),
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(curriculum_system, competency_id)
);

create index if not exists mela_curriculum_alignments_stage_idx on public.mela_curriculum_alignments(stage_key, review_status) where active;
create index if not exists mela_curriculum_alignments_competency_idx on public.mela_curriculum_alignments(competency_id);

alter table public.mela_curriculum_alignments enable row level security;

drop policy if exists mela_curriculum_alignments_read on public.mela_curriculum_alignments;
create policy mela_curriculum_alignments_read on public.mela_curriculum_alignments
for select to authenticated
using (active and review_status <> 'retired');

drop policy if exists mela_curriculum_alignments_admin_insert on public.mela_curriculum_alignments;
create policy mela_curriculum_alignments_admin_insert on public.mela_curriculum_alignments
for insert to authenticated
with check (private.is_admin_user());

drop policy if exists mela_curriculum_alignments_admin_update on public.mela_curriculum_alignments;
create policy mela_curriculum_alignments_admin_update on public.mela_curriculum_alignments
for update to authenticated
using (private.is_admin_user())
with check (private.is_admin_user());

drop policy if exists mela_curriculum_alignments_admin_delete on public.mela_curriculum_alignments;
create policy mela_curriculum_alignments_admin_delete on public.mela_curriculum_alignments
for delete to authenticated
using (private.is_admin_user());

revoke all on public.mela_curriculum_alignments from anon;
grant select on public.mela_curriculum_alignments to authenticated;
grant all on public.mela_curriculum_alignments to service_role;

insert into public.mela_curriculum_alignments(
  competency_id,curriculum_system,stage_key,subject_key,subject_title,strand_title,local_contexts,alignment_note,review_status
)
select
  c.id,
  'Ethiopia',
  c.stage_key,
  case
    when c.domain_key='literacy' then 'language_literacy'
    when c.domain_key='numeracy' then 'mathematics'
    when c.domain_key in ('science','stem') then 'science_stem'
    when c.domain_key in ('digital','ai') then 'digital_ai_literacy'
    when c.domain_key='creativity' then 'arts_design'
    when c.domain_key='learning' then 'learning_habits'
    when c.domain_key='academic' then 'cross_curricular_academic'
    when c.domain_key='projects' then 'applied_projects'
    when c.domain_key in ('future','transition','career','growth') then 'pathway_guidance'
    when c.domain_key='life' then 'life_financial_literacy'
    when c.domain_key in ('technical','safety','problem_solving','work_readiness') then 'tvet_program_specific'
    when c.domain_key in ('domain','professional') then 'higher_education_program_specific'
    else 'cross_curricular'
  end,
  case
    when c.domain_key='literacy' then 'Language, Literacy & Communication'
    when c.domain_key='numeracy' then 'Mathematics'
    when c.domain_key in ('science','stem') then 'Science & STEM'
    when c.domain_key in ('digital','ai') then 'Digital, Information & AI Literacy'
    when c.domain_key='creativity' then 'Arts, Design & Making'
    when c.domain_key='learning' then 'Learning to Learn'
    when c.domain_key='academic' then 'Cross-curricular Academic Skills'
    when c.domain_key='projects' then 'Applied Projects & Portfolio'
    when c.domain_key in ('future','transition','career','growth') then 'Education & Career Pathway Guidance'
    when c.domain_key='life' then 'Life & Financial Literacy'
    when c.stage_key='college_tvet' then 'TVET Program / Occupational Standard Mapping Required'
    when c.stage_key='university' then 'Higher-Education Program Mapping Required'
    else 'Cross-curricular Capability'
  end,
  c.domain_title,
  case
    when c.stage_key like 'school_%' then array['home','school','community','local environment']::text[]
    when c.stage_key='college_tvet' then array['workshop','workplace','local industry','community service']::text[]
    else array['campus','research','industry','community']::text[]
  end,
  'Framework bridge only. This mapping connects Mela competency evidence to an Ethiopian learning context but is not presented as Ministry-approved curriculum alignment until qualified educator and curriculum review is completed.',
  'framework'
from public.learning_competencies c
where c.content_status <> 'retired'
on conflict (curriculum_system,competency_id) do update set
  stage_key=excluded.stage_key,
  subject_key=excluded.subject_key,
  subject_title=excluded.subject_title,
  strand_title=excluded.strand_title,
  local_contexts=excluded.local_contexts,
  alignment_note=excluded.alignment_note,
  updated_at=now();

create table if not exists public.mela_local_challenge_templates (
  challenge_key text primary key,
  title text not null,
  description text not null,
  sector_key text not null,
  stage_keys text[] not null default '{}',
  competency_keys text[] not null default '{}',
  evidence_requirements text[] not null default '{}',
  local_context_note text not null,
  offline_friendly boolean not null default true,
  safeguarding_level text not null default 'standard' check (safeguarding_level in ('young_learner','school_safe','guardian_or_teacher','adult','standard')),
  content_status text not null default 'framework' check (content_status in ('framework','pilot','approved','retired')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists mela_local_challenges_stage_gin on public.mela_local_challenge_templates using gin(stage_keys);
alter table public.mela_local_challenge_templates enable row level security;

drop policy if exists mela_local_challenges_read on public.mela_local_challenge_templates;
create policy mela_local_challenges_read on public.mela_local_challenge_templates
for select to authenticated
using (active and content_status <> 'retired');

drop policy if exists mela_local_challenges_admin_insert on public.mela_local_challenge_templates;
create policy mela_local_challenges_admin_insert on public.mela_local_challenge_templates
for insert to authenticated with check (private.is_admin_user());
drop policy if exists mela_local_challenges_admin_update on public.mela_local_challenge_templates;
create policy mela_local_challenges_admin_update on public.mela_local_challenge_templates
for update to authenticated using (private.is_admin_user()) with check (private.is_admin_user());
drop policy if exists mela_local_challenges_admin_delete on public.mela_local_challenge_templates;
create policy mela_local_challenges_admin_delete on public.mela_local_challenge_templates
for delete to authenticated using (private.is_admin_user());

revoke all on public.mela_local_challenge_templates from anon;
grant select on public.mela_local_challenge_templates to authenticated;
grant all on public.mela_local_challenge_templates to service_role;

insert into public.mela_local_challenge_templates(challenge_key,title,description,sector_key,stage_keys,competency_keys,evidence_requirements,local_context_note,offline_friendly,safeguarding_level,content_status)
values
('home_water_story','Water at Home: Observe, Count, Explain','Observe safe household water uses, count or estimate simple quantities, and explain one way to reduce waste without handling unsafe water sources.','water',array['school_1_6'],array['s16_literacy','s16_numeracy','s16_science','s16_creativity'],array['short explanation','simple count or drawing','reflection'],'Use a safe home or classroom context. Do not instruct children to collect or test unsafe water. ',true,'young_learner','framework'),
('local_market_math','Local Market Math & Fair Comparison','Use fictional or teacher-provided local market prices to compare quantities, ratios and value, then explain the reasoning.','local_business',array['school_7_8'],array['s78_math','s78_literacy'],array['worked calculations','comparison explanation','reflection'],'Use fictional, public or teacher-provided prices; no child purchasing or private household financial data is required.',true,'school_safe','framework'),
('community_information_check','Community Information Verification','Compare several information claims about a locally relevant topic, identify evidence, and explain how AI or online sources should be checked.','digital_citizenship',array['school_7_8','school_9_10'],array['s78_ai','s78_literacy','s910_ai','s910_academic'],array['source comparison','verification checklist','reflection'],'Use non-sensitive public topics and teach source verification rather than political persuasion or personal profiling.',true,'school_safe','framework'),
('crop_loss_problem','Post-Harvest Loss Problem Model','Model a fictional crop-loss problem using percentages, data and a proposed low-cost improvement; communicate expected benefits and assumptions.','agriculture',array['school_9_10','school_11_12'],array['s910_stem','s910_projects','s1112_projects','s1112_life'],array['problem statement','calculations or data','solution concept','assumptions','reflection'],'Use fictional or public agricultural data unless a school/partner has permission to use real non-personal local data.',true,'school_safe','framework'),
('school_energy_audit','School Energy Improvement Proposal','Use teacher-approved observations or sample data to identify energy-saving opportunities and present an evidence-based proposal.','energy',array['school_9_10','school_11_12'],array['s910_stem','s910_projects','s1112_projects','s1112_academic'],array['baseline or sample data','analysis','proposal','presentation','reflection'],'No electrical maintenance or unsafe physical inspection. Learners analyze safe observations/sample data only.',true,'guardian_or_teacher','framework'),
('transition_budget','Education Pathway Budget & Decision Model','Compare fictional costs, time, prerequisites and benefits of several post-school pathways and explain a reasoned decision without treating the result as financial advice.','education_transition',array['school_11_12'],array['s1112_transition','s1112_life','s1112_academic'],array['pathway comparison','budget model','decision rationale','uncertainty reflection'],'Use illustrative figures or verified public costs; never ask learners to disclose family income.',true,'school_safe','framework'),
('tvet_preventive_maintenance','Preventive Maintenance Evidence Pack','Create a field-appropriate preventive-maintenance plan, safety checklist and evidence log for a teacher-approved simulated or supervised technical task.','tvet_industry',array['college_tvet'],array['tvet_technical','tvet_safety','tvet_problem','tvet_work'],array['task plan','safety checklist','evidence log','quality reflection'],'Practical work must follow institution safety rules and qualified supervision; Mela does not authorize hazardous tasks.',true,'adult','framework'),
('small_business_digitization','Local Small-Business Digitization Case','Design a simple, privacy-respecting digital workflow for a fictional or consenting local small business and estimate the operational benefit.','local_business',array['college_tvet','university'],array['tvet_digital','tvet_problem','uni_digital','uni_projects','uni_professional'],array['process map','prototype or mock-up','benefit estimate','privacy considerations','reflection'],'Use fictional data or explicit business consent; do not upload customer personal data to Mela.',true,'adult','framework'),
('campus_service_data','Campus Service Data Improvement','Analyze non-personal sample or institution-approved aggregate data about a campus service and propose a measurable improvement.','public_service',array['university'],array['uni_academic','uni_digital','uni_projects','uni_professional'],array['research question','data analysis','recommendation','limitations','presentation'],'Use aggregate/non-personal data and obtain institutional approval for any real operational dataset.',true,'adult','framework'),
('ethiopian_problem_capstone','Ethiopian Problem-Solving Capstone','Define a locally relevant education, agriculture, water, health, mobility, climate or enterprise problem; gather safe evidence; build and test a solution; document results and limitations.','cross_sector',array['school_11_12','college_tvet','university'],array['s1112_projects','tvet_problem','uni_projects'],array['problem definition','evidence','prototype or intervention','test results','limitations','reflection'],'Projects require stage-appropriate supervision, privacy protection, safety review and domain expertise when the topic could affect health, infrastructure or vulnerable people.',true,'guardian_or_teacher','framework')
on conflict (challenge_key) do update set
 title=excluded.title,description=excluded.description,sector_key=excluded.sector_key,stage_keys=excluded.stage_keys,competency_keys=excluded.competency_keys,evidence_requirements=excluded.evidence_requirements,local_context_note=excluded.local_context_note,offline_friendly=excluded.offline_friendly,safeguarding_level=excluded.safeguarding_level,updated_at=now();

alter table public.education_benchmark_adaptations
  add column if not exists ethiopia_validation_status text not null default 'unvalidated',
  add column if not exists ethiopia_validation_note text,
  add column if not exists ethiopia_validated_at timestamptz;

do $$ begin
  if not exists (select 1 from pg_constraint where conname='education_benchmark_adaptations_eth_validation_check') then
    alter table public.education_benchmark_adaptations add constraint education_benchmark_adaptations_eth_validation_check
    check (ethiopia_validation_status in ('unvalidated','pilot','supported','inconclusive','rejected'));
  end if;
end $$;

update public.education_benchmark_adaptations
set ethiopia_validation_status='unvalidated',
    ethiopia_validation_note=coalesce(ethiopia_validation_note,'Implemented or planned as a Mela design adaptation; not yet claimed as locally proven until Ethiopian pilot evidence is reviewed.'),
    ethiopia_validated_at=null
where ethiopia_validation_status is null or ethiopia_validation_status not in ('supported','inconclusive','rejected');

create table if not exists public.mela_impact_measurements (
  id uuid primary key default gen_random_uuid(),
  partner_organization_id uuid not null references public.sector_partner_organizations(id) on delete cascade,
  metric_key text not null references public.mela_outcome_metrics(metric_key) on delete restrict,
  stage_key text references public.education_audience_stages(stage_key) on delete set null,
  period_start date not null,
  period_end date not null,
  sample_size integer not null check (sample_size >= 0),
  baseline_value numeric,
  end_value numeric,
  change_value numeric generated always as (case when baseline_value is null or end_value is null then null else end_value-baseline_value end) stored,
  methodology text not null,
  evidence_note text,
  source_reference text,
  validation_status text not null default 'draft' check (validation_status in ('draft','reviewed','supported','inconclusive','rejected')),
  measured_by uuid references public.profiles(id) on delete set null,
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (period_end >= period_start)
);
create index if not exists mela_impact_measurements_org_period_idx on public.mela_impact_measurements(partner_organization_id,period_end desc);
create index if not exists mela_impact_measurements_metric_idx on public.mela_impact_measurements(metric_key,validation_status);
create index if not exists mela_impact_measurements_stage_idx on public.mela_impact_measurements(stage_key) where stage_key is not null;
alter table public.mela_impact_measurements enable row level security;

drop policy if exists mela_impact_measurements_read on public.mela_impact_measurements;
create policy mela_impact_measurements_read on public.mela_impact_measurements
for select to authenticated
using (
  private.is_admin_user()
  or (
    private.has_sector_partner_membership(partner_organization_id,(select auth.uid()),false)
    and sample_size >= coalesce((select m.privacy_threshold from public.mela_outcome_metrics m where m.metric_key=mela_impact_measurements.metric_key),10)
  )
);
drop policy if exists mela_impact_measurements_admin_insert on public.mela_impact_measurements;
create policy mela_impact_measurements_admin_insert on public.mela_impact_measurements
for insert to authenticated with check (private.is_admin_user());
drop policy if exists mela_impact_measurements_admin_update on public.mela_impact_measurements;
create policy mela_impact_measurements_admin_update on public.mela_impact_measurements
for update to authenticated using (private.is_admin_user()) with check (private.is_admin_user());
drop policy if exists mela_impact_measurements_admin_delete on public.mela_impact_measurements;
create policy mela_impact_measurements_admin_delete on public.mela_impact_measurements
for delete to authenticated using (private.is_admin_user());

revoke all on public.mela_impact_measurements from anon;
grant select on public.mela_impact_measurements to authenticated;
grant all on public.mela_impact_measurements to service_role;

create or replace function public.get_my_education_os_v2()
returns jsonb
language plpgsql
stable
set search_path=''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_stage text;
  v_home jsonb;
  v_approved_count integer;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select education_stage_key into v_stage from public.profiles where id=v_uid;
  if v_stage is null then return jsonb_build_object('home',public.get_my_learning_home_v3(),'curriculum_bridge','[]'::jsonb,'local_challenges','[]'::jsonb,'value_loop',jsonb_build_array('onboard','diagnose','learn','practice','master','build','prove','plan','progress','measure'),'impact_truth','Mela does not claim educational impact for a learner or institution until real local evidence has been measured and reviewed.'); end if;
  v_home := public.get_my_learning_home_v3();
  select count(*) into v_approved_count from public.mela_curriculum_alignments a where a.stage_key=v_stage and a.active and a.review_status='approved';
  return jsonb_build_object(
    'version','2026.08-education-os-v2',
    'home',v_home,
    'curriculum_bridge',coalesce((select jsonb_agg(jsonb_build_object(
      'competency_id',a.competency_id,'competency_key',c.competency_key,'competency_title',c.title,
      'subject_key',a.subject_key,'subject_title',a.subject_title,'strand_title',a.strand_title,
      'review_status',a.review_status,'alignment_note',a.alignment_note,'source_reference',a.source_reference,
      'local_contexts',a.local_contexts
    ) order by c.display_order) from public.mela_curriculum_alignments a join public.learning_competencies c on c.id=a.competency_id where a.stage_key=v_stage and a.active and a.review_status<>'retired'),'[]'::jsonb),
    'curriculum_status',jsonb_build_object(
      'approved_alignments',v_approved_count,
      'stage_alignment_count',(select count(*) from public.mela_curriculum_alignments a where a.stage_key=v_stage and a.active and a.review_status<>'retired'),
      'claim',case when v_approved_count>0 then 'Some mappings have completed the configured review workflow; verify each item status.' else 'Framework bridge only — not presented as Ministry-approved curriculum alignment.' end
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
      jsonb_build_object('step','learn','system','Stage and curriculum-context learning'),
      jsonb_build_object('step','practice','system','Targeted practice and catch-up'),
      jsonb_build_object('step','master','system','Evidence-weighted Mastery Engine'),
      jsonb_build_object('step','build','system','Ethiopian-context projects'),
      jsonb_build_object('step','prove','system','Learner Passport and verified evidence'),
      jsonb_build_object('step','plan','system','Mela Next'),
      jsonb_build_object('step','progress','system','Opportunity Graph / education transition'),
      jsonb_build_object('step','measure','system','Privacy-protected outcome measurement')
    ),
    'impact_truth','Mela is technically designed to create and measure educational value, but local sector impact is not considered proven until Ethiopian pilots produce reviewed before/after evidence with adequate sample sizes.'
  );
end;
$$;

create or replace function public.get_my_partner_education_impact()
returns jsonb
language sql
stable
set search_path=''
as $$
with me as (select auth.uid() uid),
orgs as (
 select o.id,o.organization_name,o.partner_type_key
 from public.sector_partner_organizations o
 join public.sector_partner_members m on m.partner_organization_id=o.id
 cross join me
 where m.user_id=me.uid and m.status='active' and o.partner_type_key in ('school','college_tvet','university')
), measurements as (
 select x.*,m.title metric_title,m.unit,m.direction,m.target_value,m.privacy_threshold
 from public.mela_impact_measurements x
 join public.mela_outcome_metrics m on m.metric_key=x.metric_key
 where x.partner_organization_id in (select id from orgs)
   and x.sample_size>=m.privacy_threshold
), snapshots as (
 select s.* from public.institution_outcome_snapshots s where s.partner_organization_id in(select id from orgs)
)
select jsonb_build_object(
 'organizations',coalesce((select jsonb_agg(to_jsonb(o) order by o.organization_name) from orgs o),'[]'::jsonb),
 'measurement_count',(select count(*) from measurements),
 'reviewed_measurement_count',(select count(*) from measurements where validation_status in ('reviewed','supported','inconclusive','rejected')),
 'supported_measurement_count',(select count(*) from measurements where validation_status='supported'),
 'impact_claim',case when exists(select 1 from measurements where validation_status='supported') then 'Reviewed local measurements include supported improvement. Interpret by metric, sample size and method.' else 'No locally supported impact claim is available yet. The dashboard will remain evidence-first until reviewed pilot measurements exist.' end,
 'measurements',coalesce((select jsonb_agg(jsonb_build_object(
   'id',m.id,'organization_id',m.partner_organization_id,'metric_key',m.metric_key,'metric_title',m.metric_title,
   'stage_key',m.stage_key,'period_start',m.period_start,'period_end',m.period_end,'sample_size',m.sample_size,
   'baseline_value',m.baseline_value,'end_value',m.end_value,'change_value',m.change_value,'unit',m.unit,'direction',m.direction,
   'target_value',m.target_value,'methodology',m.methodology,'evidence_note',m.evidence_note,'source_reference',m.source_reference,
   'validation_status',m.validation_status,'reviewed_at',m.reviewed_at
 ) order by m.period_end desc,m.metric_key) from measurements m),'[]'::jsonb),
 'latest_snapshots',coalesce((select jsonb_agg(to_jsonb(s) order by s.period_end desc) from (select * from snapshots order by period_end desc limit 12)s),'[]'::jsonb),
 'defined_metrics',coalesce((select jsonb_agg(jsonb_build_object('metric_key',x.metric_key,'title',x.title,'description',x.description,'unit',x.unit,'direction',x.direction,'target_value',x.target_value,'privacy_threshold',x.privacy_threshold) order by x.engine_key,x.metric_key) from public.mela_outcome_metrics x where x.active),'[]'::jsonb)
);
$$;

create or replace function public.admin_education_value_readiness_v2()
returns jsonb
language plpgsql
stable
set search_path=''
as $$
declare
  v_real_students integer;
  v_real_educators integer;
  v_real_partners integer;
  v_ready_tracks integer;
  v_supported integer;
  v_reviewed integer;
  v_non_en_cert integer;
  v_offline integer;
  v_curriculum_approved integer;
  v_score numeric;
begin
  if not private.is_admin_user() then raise exception 'admin access required'; end if;
  select count(*) into v_real_students from public.profiles where role='student' and lower(coalesce(email,'')) not like '%@mela.invalid';
  select count(*) into v_real_educators from public.educator_profiles ep join public.profiles p on p.id=ep.user_id where ep.verified and ep.active and lower(coalesce(p.email,'')) not like '%@mela.invalid';
  select count(*) into v_real_partners from public.sector_partner_organizations o join public.profiles p on p.id=o.owner_id where o.partner_type_key in ('school','college_tvet','university') and o.verification_status='verified' and lower(coalesce(p.email,'')) not like '%@mela.invalid';
  select count(*) into v_ready_tracks from public.audience_learning_tracks where content_status in ('published','approved','active');
  select count(*) into v_supported from public.mela_impact_measurements where validation_status='supported';
  select count(*) into v_reviewed from public.mela_impact_measurements where validation_status in ('reviewed','supported','inconclusive','rejected');
  select count(*) into v_non_en_cert from public.assessment_language_certifications where language_code<>'en' and status='certified';
  select count(*) into v_offline from public.mela_offline_content_packs where published;
  select count(*) into v_curriculum_approved from public.mela_curriculum_alignments where active and review_status='approved';
  v_score := round((
    (case when (select count(*) from public.learning_competencies where content_status<>'retired')>=36 then 20 else 10 end)+
    (case when v_ready_tracks>=20 then 20 when v_ready_tracks>0 then 10 else 0 end)+
    (case when v_non_en_cert>=32 then 15 when v_non_en_cert>0 then 7 else 0 end)+
    (case when v_curriculum_approved>=24 then 15 when v_curriculum_approved>0 then 7 else 0 end)+
    (case when v_real_students>=100 and v_real_educators>=5 and v_real_partners>=1 then 15 when v_real_students>0 then 5 else 0 end)+
    (case when v_reviewed>0 then 10 else 0 end)+
    (case when v_offline>0 then 5 else 0 end)
  )::numeric,0);
  return jsonb_build_object(
   'generated_at',now(),'readiness_score',v_score,
   'technical_capability',jsonb_build_object('competencies',(select count(*) from public.learning_competencies where content_status<>'retired'),'engines',(select count(*) from public.mela_education_engines),'benchmark_adaptations',(select count(*) from public.education_benchmark_adaptations where active),'outcome_metrics',(select count(*) from public.mela_outcome_metrics where active)),
   'curriculum_content',jsonb_build_object('learning_tracks',(select count(*) from public.audience_learning_tracks),'ready_tracks',v_ready_tracks,'curriculum_bridge_rows',(select count(*) from public.mela_curriculum_alignments where active),'approved_curriculum_mappings',v_curriculum_approved,'local_challenge_templates',(select count(*) from public.mela_local_challenge_templates where active),'approved_or_pilot_challenges',(select count(*) from public.mela_local_challenge_templates where active and content_status in ('approved','pilot'))),
   'language_quality',jsonb_build_object('enabled_languages',(select count(*) from public.platform_languages where enabled),'certified_non_english_assessments',v_non_en_cert),
   'real_pilot_supply',jsonb_build_object('real_students',v_real_students,'verified_real_educators',v_real_educators,'verified_real_education_partners',v_real_partners),
   'impact_evidence',jsonb_build_object('measurements',(select count(*) from public.mela_impact_measurements),'reviewed_measurements',v_reviewed,'supported_measurements',v_supported,'institution_snapshots',(select count(*) from public.institution_outcome_snapshots),'sector_impact_proven',(v_supported>0)),
   'low_bandwidth',jsonb_build_object('published_offline_packs',v_offline,'sync_records',(select count(*) from public.learner_offline_sync_state)),
   'verdict',case when v_supported>0 and v_real_students>=100 and v_ready_tracks>=20 and v_non_en_cert>=32 and v_curriculum_approved>=24 then 'impact_evidence_ready' when v_real_students>0 or v_reviewed>0 then 'pilot_evidence_building' else 'technically_capable_not_yet_locally_proven' end,
   'blockers',jsonb_build_array(
     case when v_ready_tracks=0 then 'Complete and approve real Grades 1–12 / higher-education learning content and question banks.' end,
     case when v_curriculum_approved=0 then 'Complete qualified Ethiopian educator/curriculum review; current curriculum bridge is framework-only.' end,
     case when v_non_en_cert<32 then 'Complete independent human certification for Amharic, Afaan Oromo, Tigrinya and Somali credential assessments.' end,
     case when v_real_students=0 or v_real_educators=0 or v_real_partners=0 then 'Run a real Ethiopian education pilot with learners, educators and at least one verified institution.' end,
     case when v_reviewed=0 then 'Collect privacy-protected before/after outcome measurements with documented methodology.' end,
     case when v_offline=0 then 'Publish reviewed low-bandwidth/offline learning packs after content approval.' end
   )
  );
end;
$$;

-- Wire partner impact navigation to an implemented route in the production candidate.
update public.platform_audience_subsections
set route_key='education-impact'
where subsection_key='partner_impact_dashboard';

update public.mela_education_engines
set current_assets=current_assets || jsonb_build_object('curriculum_bridge','mela_curriculum_alignments','local_projects','mela_local_challenge_templates','learner_os_rpc','get_my_education_os_v2'),updated_at=now()
where engine_key in ('mastery','projects_impact','passport');

update public.mela_education_engines
set current_assets=current_assets || jsonb_build_object('impact_measurements','mela_impact_measurements','partner_rpc','get_my_partner_education_impact','admin_readiness_rpc','admin_education_value_readiness_v2'),updated_at=now()
where engine_key='institution_outcomes';

create or replace function public.admin_education_system_snapshot()
returns jsonb
language plpgsql
stable
set search_path=''
as $$
begin
  if not private.is_admin_user() then raise exception 'admin access required'; end if;
  return jsonb_build_object(
    'generated_at',now(),
    'benchmark',jsonb_build_object(
      'countries',(select count(*) from public.education_benchmark_systems where active),
      'source_practices',(select count(*) from public.education_benchmark_practices where active),
      'adaptations',(select count(*) from public.education_benchmark_adaptations where active),
      'locally_supported_adaptations',(select count(*) from public.education_benchmark_adaptations where active and ethiopia_validation_status='supported'),
      'adaptation_status',(select coalesce(jsonb_object_agg(implementation_status,cnt),'{}'::jsonb) from (select implementation_status,count(*) cnt from public.education_benchmark_adaptations where active group by implementation_status)s),
      'local_validation_status',(select coalesce(jsonb_object_agg(ethiopia_validation_status,cnt),'{}'::jsonb) from (select ethiopia_validation_status,count(*) cnt from public.education_benchmark_adaptations where active group by ethiopia_validation_status)s),
      'engines',(select jsonb_object_agg(implementation_status,cnt) from (select implementation_status,count(*) cnt from public.mela_education_engines group by implementation_status)s)
    ),
    'curriculum',jsonb_build_object(
      'bridge_rows',(select count(*) from public.mela_curriculum_alignments where active),
      'approved_mappings',(select count(*) from public.mela_curriculum_alignments where active and review_status='approved'),
      'framework_mappings',(select count(*) from public.mela_curriculum_alignments where active and review_status='framework'),
      'local_challenges',(select count(*) from public.mela_local_challenge_templates where active),
      'approved_or_pilot_challenges',(select count(*) from public.mela_local_challenge_templates where active and content_status in ('approved','pilot'))
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
      'impact_measurements',(select count(*) from public.mela_impact_measurements),
      'reviewed_impact_measurements',(select count(*) from public.mela_impact_measurements where validation_status in ('reviewed','supported','inconclusive','rejected')),
      'supported_impact_measurements',(select count(*) from public.mela_impact_measurements where validation_status='supported'),
      'defined_metrics',(select count(*) from public.mela_outcome_metrics where active)
    ),
    'offline',jsonb_build_object(
      'published_packs',(select count(*) from public.mela_offline_content_packs where published),
      'sync_states',(select count(*) from public.learner_offline_sync_state)
    )
  );
end;
$$;

-- New public-schema functions are not anonymous APIs.
revoke all on function public.get_my_education_os_v2() from public,anon;
grant execute on function public.get_my_education_os_v2() to authenticated,service_role;
revoke all on function public.get_my_partner_education_impact() from public,anon;
grant execute on function public.get_my_partner_education_impact() to authenticated,service_role;
revoke all on function public.admin_education_value_readiness_v2() from public,anon;
grant execute on function public.admin_education_value_readiness_v2() to authenticated,service_role;
revoke all on function public.admin_education_system_snapshot() from public,anon;
grant execute on function public.admin_education_system_snapshot() to authenticated,service_role;
;
