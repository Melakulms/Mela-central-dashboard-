-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815050024
-- Operationalize intervention tracking and build privacy-aware education pilot evaluation.
alter table public.mela_learning_interventions
  add column if not exists source_entity_type text,
  add column if not exists source_entity_id uuid;
create unique index if not exists mela_learning_interventions_source_entity_uidx
  on public.mela_learning_interventions(user_id,source_entity_type,source_entity_id)
  where source_entity_id is not null;

create or replace function private.sync_catchup_plan_intervention()
returns trigger
language plpgsql
set search_path to ''
as $$
begin
  insert into public.mela_learning_interventions(
    user_id,intervention_type,source,rationale,status,recommended_at,started_at,completed_at,
    source_entity_type,source_entity_id,metadata,created_at,updated_at
  ) values (
    new.user_id,'catchup','mela_system',new.rationale,
    case new.status when 'draft' then 'recommended' when 'active' then 'in_progress' when 'completed' then 'completed' when 'cancelled' then 'cancelled' else 'recommended' end,
    new.created_at,
    case when new.status in ('active','completed') then new.created_at else null end,
    new.completed_at,
    'learner_catchup_plan',new.id,
    jsonb_build_object('title',new.title,'stage_key',new.stage_key,'duration_weeks',new.duration_weeks),
    new.created_at,now()
  )
  on conflict (user_id,source_entity_type,source_entity_id) where source_entity_id is not null
  do update set
    rationale=excluded.rationale,
    status=excluded.status,
    started_at=coalesce(public.mela_learning_interventions.started_at,excluded.started_at),
    completed_at=excluded.completed_at,
    metadata=excluded.metadata,
    updated_at=now();
  return new;
end;
$$;

drop trigger if exists trg_catchup_plan_intervention on public.learner_catchup_plans;
create trigger trg_catchup_plan_intervention
after insert or update of status,rationale,title,duration_weeks on public.learner_catchup_plans
for each row execute function private.sync_catchup_plan_intervention();

-- Backfill existing plans without generating duplicates.
insert into public.mela_learning_interventions(
  user_id,intervention_type,source,rationale,status,recommended_at,started_at,completed_at,
  source_entity_type,source_entity_id,metadata,created_at,updated_at
)
select p.user_id,'catchup','mela_system',p.rationale,
       case p.status when 'draft' then 'recommended' when 'active' then 'in_progress' when 'completed' then 'completed' when 'cancelled' then 'cancelled' else 'recommended' end,
       p.created_at,case when p.status in ('active','completed') then p.created_at end,p.completed_at,
       'learner_catchup_plan',p.id,jsonb_build_object('title',p.title,'stage_key',p.stage_key,'duration_weeks',p.duration_weeks),p.created_at,now()
from public.learner_catchup_plans p
on conflict (user_id,source_entity_type,source_entity_id) where source_entity_id is not null do nothing;

create table if not exists public.mela_education_pilots (
  id uuid primary key default gen_random_uuid(),
  partner_organization_id uuid not null references public.sector_partner_organizations(id) on delete cascade,
  title text not null,
  description text,
  stage_keys text[] not null default '{}',
  evaluation_design text not null default 'before_after' check (evaluation_design in ('before_after','matched_comparison','stepped_rollout','descriptive')),
  status text not null default 'draft' check (status in ('draft','recruiting','active','completed','paused','cancelled')),
  start_date date,
  end_date date,
  minimum_sample_size integer not null default 30 check (minimum_sample_size >= 10),
  consent_and_ethics_note text,
  methodology_note text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint mela_education_pilots_dates check (end_date is null or start_date is null or end_date >= start_date)
);

create table if not exists public.mela_education_pilot_cohorts (
  id uuid primary key default gen_random_uuid(),
  pilot_id uuid not null references public.mela_education_pilots(id) on delete cascade,
  cohort_key text not null,
  title text not null,
  cohort_type text not null default 'intervention' check (cohort_type in ('intervention','comparison','rollout_later')),
  stage_key text references public.education_audience_stages(stage_key) on delete restrict,
  grade_level smallint check (grade_level is null or grade_level between 1 and 12),
  target_sample_size integer check (target_sample_size is null or target_sample_size >= 1),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique(pilot_id,cohort_key)
);

create table if not exists public.mela_education_pilot_metrics (
  pilot_id uuid not null references public.mela_education_pilots(id) on delete cascade,
  metric_key text not null references public.mela_outcome_metrics(metric_key) on delete restrict,
  primary_metric boolean not null default false,
  target_value numeric,
  notes text,
  primary key(pilot_id,metric_key)
);

create table if not exists public.mela_education_pilot_measurements (
  id uuid primary key default gen_random_uuid(),
  pilot_id uuid not null references public.mela_education_pilots(id) on delete cascade,
  cohort_id uuid references public.mela_education_pilot_cohorts(id) on delete cascade,
  metric_key text not null references public.mela_outcome_metrics(metric_key) on delete restrict,
  measurement_period text not null check (measurement_period in ('baseline','midline','endline','followup')),
  measured_on date not null,
  value numeric not null,
  sample_size integer not null check (sample_size >= 1),
  methodology text,
  evidence_note text,
  data_quality text not null default 'provisional' check (data_quality in ('provisional','reviewed','verified','invalid')),
  recorded_by uuid references public.profiles(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique(pilot_id,cohort_id,metric_key,measurement_period,measured_on)
);

create index if not exists mela_education_pilots_partner_status_idx on public.mela_education_pilots(partner_organization_id,status,start_date desc);
create index if not exists mela_education_pilots_created_by_idx on public.mela_education_pilots(created_by);
create index if not exists mela_education_pilot_cohorts_pilot_idx on public.mela_education_pilot_cohorts(pilot_id,cohort_type);
create index if not exists mela_education_pilot_measurements_pilot_metric_idx on public.mela_education_pilot_measurements(pilot_id,metric_key,measured_on);
create index if not exists mela_education_pilot_measurements_cohort_idx on public.mela_education_pilot_measurements(cohort_id);
create index if not exists mela_education_pilot_measurements_recorded_by_idx on public.mela_education_pilot_measurements(recorded_by);

alter table public.mela_education_pilots enable row level security;
alter table public.mela_education_pilot_cohorts enable row level security;
alter table public.mela_education_pilot_metrics enable row level security;
alter table public.mela_education_pilot_measurements enable row level security;

revoke all on public.mela_education_pilots from anon,authenticated;
revoke all on public.mela_education_pilot_cohorts from anon,authenticated;
revoke all on public.mela_education_pilot_metrics from anon,authenticated;
revoke all on public.mela_education_pilot_measurements from anon,authenticated;
grant select,insert,update on public.mela_education_pilots to authenticated;
grant select,insert,update on public.mela_education_pilot_cohorts to authenticated;
grant select,insert,update on public.mela_education_pilot_metrics to authenticated;
grant select,insert,update on public.mela_education_pilot_measurements to authenticated;

create policy mela_education_pilots_read on public.mela_education_pilots for select to authenticated
using (private.is_admin_user() or private.has_sector_partner_membership(partner_organization_id,(select auth.uid()),false));
create policy mela_education_pilots_insert on public.mela_education_pilots for insert to authenticated
with check (private.is_admin_user() or private.has_sector_partner_membership(partner_organization_id,(select auth.uid()),true));
create policy mela_education_pilots_update on public.mela_education_pilots for update to authenticated
using (private.is_admin_user() or private.has_sector_partner_membership(partner_organization_id,(select auth.uid()),true))
with check (private.is_admin_user() or private.has_sector_partner_membership(partner_organization_id,(select auth.uid()),true));

create policy mela_education_pilot_cohorts_read on public.mela_education_pilot_cohorts for select to authenticated
using (exists(select 1 from public.mela_education_pilots p where p.id=pilot_id));
create policy mela_education_pilot_cohorts_insert on public.mela_education_pilot_cohorts for insert to authenticated
with check (exists(select 1 from public.mela_education_pilots p where p.id=pilot_id and (private.is_admin_user() or private.has_sector_partner_membership(p.partner_organization_id,(select auth.uid()),true))));
create policy mela_education_pilot_cohorts_update on public.mela_education_pilot_cohorts for update to authenticated
using (exists(select 1 from public.mela_education_pilots p where p.id=pilot_id and (private.is_admin_user() or private.has_sector_partner_membership(p.partner_organization_id,(select auth.uid()),true))))
with check (exists(select 1 from public.mela_education_pilots p where p.id=pilot_id and (private.is_admin_user() or private.has_sector_partner_membership(p.partner_organization_id,(select auth.uid()),true))));

create policy mela_education_pilot_metrics_read on public.mela_education_pilot_metrics for select to authenticated
using (exists(select 1 from public.mela_education_pilots p where p.id=pilot_id));
create policy mela_education_pilot_metrics_insert on public.mela_education_pilot_metrics for insert to authenticated
with check (exists(select 1 from public.mela_education_pilots p where p.id=pilot_id and (private.is_admin_user() or private.has_sector_partner_membership(p.partner_organization_id,(select auth.uid()),true))));
create policy mela_education_pilot_metrics_update on public.mela_education_pilot_metrics for update to authenticated
using (exists(select 1 from public.mela_education_pilots p where p.id=pilot_id and (private.is_admin_user() or private.has_sector_partner_membership(p.partner_organization_id,(select auth.uid()),true))))
with check (exists(select 1 from public.mela_education_pilots p where p.id=pilot_id and (private.is_admin_user() or private.has_sector_partner_membership(p.partner_organization_id,(select auth.uid()),true))));

create policy mela_education_pilot_measurements_read on public.mela_education_pilot_measurements for select to authenticated
using (exists(select 1 from public.mela_education_pilots p where p.id=pilot_id));
create policy mela_education_pilot_measurements_insert on public.mela_education_pilot_measurements for insert to authenticated
with check (
  exists(select 1 from public.mela_education_pilots p where p.id=pilot_id and (private.is_admin_user() or private.has_sector_partner_membership(p.partner_organization_id,(select auth.uid()),true)))
  and sample_size >= coalesce((select privacy_threshold from public.mela_outcome_metrics m where m.metric_key=mela_education_pilot_measurements.metric_key),10)
);
create policy mela_education_pilot_measurements_update on public.mela_education_pilot_measurements for update to authenticated
using (exists(select 1 from public.mela_education_pilots p where p.id=pilot_id and (private.is_admin_user() or private.has_sector_partner_membership(p.partner_organization_id,(select auth.uid()),true))))
with check (
  exists(select 1 from public.mela_education_pilots p where p.id=pilot_id and (private.is_admin_user() or private.has_sector_partner_membership(p.partner_organization_id,(select auth.uid()),true)))
  and sample_size >= coalesce((select privacy_threshold from public.mela_outcome_metrics m where m.metric_key=mela_education_pilot_measurements.metric_key),10)
);

create or replace function public.get_my_partner_education_outcomes()
returns jsonb
language plpgsql
stable
set search_path to ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_org public.sector_partner_organizations%rowtype;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select o.* into v_org
  from public.sector_partner_organizations o
  join public.sector_partner_members m on m.partner_organization_id=o.id
  where m.user_id=v_uid and m.status='active'
  order by (m.member_role='owner') desc,o.created_at limit 1;
  if not found then raise exception 'active sector partner organization required'; end if;
  return jsonb_build_object(
    'organization',jsonb_build_object('id',v_org.id,'name',v_org.organization_name,'partner_type_key',v_org.partner_type_key,'verification_status',v_org.verification_status),
    'education_partner',v_org.partner_type_key in ('school','college_tvet','university'),
    'curriculum',jsonb_build_object(
      'official_alignment_status',(select alignment_status from public.mela_curriculum_frameworks where framework_key='ethiopia_national_alignment'),
      'mela_core_objectives',(select count(*) from public.mela_curriculum_objectives where content_status='published'),
      'official_subject_listings',(select count(*) from public.mela_national_subject_catalog where active)
    ),
    'defined_metrics',coalesce((select jsonb_agg(jsonb_build_object('metric_key',m.metric_key,'title',m.title,'description',m.description,'unit',m.unit,'direction',m.direction,'privacy_threshold',m.privacy_threshold) order by m.engine_key,m.metric_key) from public.mela_outcome_metrics m where m.active),'[]'::jsonb),
    'outcome_snapshots',coalesce((select jsonb_agg(to_jsonb(s) order by s.period_end desc) from (select * from public.institution_outcome_snapshots where partner_organization_id=v_org.id order by period_end desc limit 24)s),'[]'::jsonb),
    'pilots',coalesce((select jsonb_agg(jsonb_build_object(
      'id',p.id,'title',p.title,'description',p.description,'stage_keys',p.stage_keys,'evaluation_design',p.evaluation_design,'status',p.status,
      'start_date',p.start_date,'end_date',p.end_date,'minimum_sample_size',p.minimum_sample_size,
      'cohorts',(select count(*) from public.mela_education_pilot_cohorts c where c.pilot_id=p.id),
      'measurements',(select count(*) from public.mela_education_pilot_measurements x where x.pilot_id=p.id)
    ) order by p.created_at desc) from public.mela_education_pilots p where p.partner_organization_id=v_org.id),'[]'::jsonb)
  );
end;
$$;

create or replace function public.admin_education_value_readiness_v3()
returns jsonb
language plpgsql
stable
set search_path to ''
as $$
declare
  v_base jsonb;
  v_checks jsonb;
  v_real_active_pilots integer;
  v_verified_measurements integer;
begin
  if not private.is_admin_user() then raise exception 'admin access required'; end if;
  v_base := public.admin_education_value_readiness_v2();
  select count(*) into v_real_active_pilots
  from public.mela_education_pilots p join public.sector_partner_organizations o on o.id=p.partner_organization_id
  where p.status in ('active','completed') and o.verification_status='verified';
  select count(*) into v_verified_measurements from public.mela_education_pilot_measurements where data_quality='verified';
  v_checks := (v_base->'checks') || jsonb_build_array(
    jsonb_build_object('key','impact_evaluation_protocol','title','Real-world impact evaluation protocol','status',case when to_regclass('public.mela_education_pilots') is not null then 'foundation' else 'gap' end,'evidence','baseline / midline / endline / follow-up aggregate measurements','required','implemented','why','Mela needs a repeatable way to measure whether learning, intervention and transition outcomes improve in real institutions.'),
    jsonb_build_object('key','real_pilot_measurements','title','Verified real pilot outcome measurements','status',case when v_real_active_pilots>0 and v_verified_measurements>0 then 'pilot' else 'external_blocker' end,'evidence',jsonb_build_object('active_or_completed_verified_partner_pilots',v_real_active_pilots,'verified_measurements',v_verified_measurements),'required','at least one real institution pilot with verified baseline and follow-up evidence','why','Technical capability is not the same as demonstrated sector impact; real measurements are required before strong impact claims.')
  );
  return jsonb_build_object(
    'generated_at',now(),'value_thesis',v_base->>'value_thesis','checks',v_checks,
    'summary',(v_base->'summary') || jsonb_build_object(
      'real_active_or_completed_pilots',v_real_active_pilots,'verified_pilot_measurements',v_verified_measurements,
      'ready_or_foundation',(select count(*) from jsonb_array_elements(v_checks) x where x->>'status' in ('ready','foundation','pilot')),
      'gaps',(select count(*) from jsonb_array_elements(v_checks) x where x->>'status'='gap'),
      'external_blockers',(select count(*) from jsonb_array_elements(v_checks) x where x->>'status'='external_blocker'),
      'impact_claim_status',case when (select count(*) from jsonb_array_elements(v_checks) x where x->>'status' in ('gap','external_blocker'))=0 then 'evidence_ready' else 'not_yet_proven' end
    )
  );
end;
$$;

revoke all on function public.get_my_partner_education_outcomes() from public;
revoke all on function public.admin_education_value_readiness_v3() from public;
grant execute on function public.get_my_partner_education_outcomes() to authenticated;
grant execute on function public.admin_education_value_readiness_v3() to authenticated;

;
