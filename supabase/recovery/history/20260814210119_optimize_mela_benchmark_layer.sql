-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260814210119
create index if not exists institution_outcome_snapshots_stage_idx on public.institution_outcome_snapshots(stage_key);
create index if not exists learning_competency_capabilities_capability_idx on public.learning_competency_capabilities(capability_key);
create index if not exists learning_offline_packs_language_idx on public.learning_offline_packs(language_code);

drop policy if exists mela_core_capabilities_admin_write on public.mela_core_capabilities;
drop policy if exists learning_competency_capabilities_admin_write on public.learning_competency_capabilities;
drop policy if exists benchmark_adaptations_admin_write on public.education_benchmark_adaptations;
drop policy if exists mela_learning_cycle_admin_write on public.mela_learning_cycle_steps;
drop policy if exists institution_outcomes_admin_write on public.institution_outcome_snapshots;
drop policy if exists offline_packs_admin_write on public.learning_offline_packs;

create policy mela_core_capabilities_admin_insert on public.mela_core_capabilities for insert to authenticated with check (private.is_admin_user());
create policy mela_core_capabilities_admin_update on public.mela_core_capabilities for update to authenticated using (private.is_admin_user()) with check (private.is_admin_user());
create policy mela_core_capabilities_admin_delete on public.mela_core_capabilities for delete to authenticated using (private.is_admin_user());

create policy learning_competency_capabilities_admin_insert on public.learning_competency_capabilities for insert to authenticated with check (private.is_admin_user());
create policy learning_competency_capabilities_admin_update on public.learning_competency_capabilities for update to authenticated using (private.is_admin_user()) with check (private.is_admin_user());
create policy learning_competency_capabilities_admin_delete on public.learning_competency_capabilities for delete to authenticated using (private.is_admin_user());

create policy benchmark_adaptations_admin_insert on public.education_benchmark_adaptations for insert to authenticated with check (private.is_admin_user());
create policy benchmark_adaptations_admin_update on public.education_benchmark_adaptations for update to authenticated using (private.is_admin_user()) with check (private.is_admin_user());
create policy benchmark_adaptations_admin_delete on public.education_benchmark_adaptations for delete to authenticated using (private.is_admin_user());

create policy mela_learning_cycle_admin_insert on public.mela_learning_cycle_steps for insert to authenticated with check (private.is_admin_user());
create policy mela_learning_cycle_admin_update on public.mela_learning_cycle_steps for update to authenticated using (private.is_admin_user()) with check (private.is_admin_user());
create policy mela_learning_cycle_admin_delete on public.mela_learning_cycle_steps for delete to authenticated using (private.is_admin_user());

create policy institution_outcomes_admin_insert on public.institution_outcome_snapshots for insert to authenticated with check (private.is_admin_user());
create policy institution_outcomes_admin_update on public.institution_outcome_snapshots for update to authenticated using (private.is_admin_user()) with check (private.is_admin_user());
create policy institution_outcomes_admin_delete on public.institution_outcome_snapshots for delete to authenticated using (private.is_admin_user());

create policy offline_packs_admin_insert on public.learning_offline_packs for insert to authenticated with check (private.is_admin_user());
create policy offline_packs_admin_update on public.learning_offline_packs for update to authenticated using (private.is_admin_user()) with check (private.is_admin_user());
create policy offline_packs_admin_delete on public.learning_offline_packs for delete to authenticated using (private.is_admin_user());

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
               round(coalesce(
                 sum(case when lc.id is not null then coalesce(m.mastery_score,0)*map.weight else 0 end)
                 / nullif(sum(case when lc.id is not null then map.weight else 0 end),0),0),2) as score,
               round(coalesce(sum(case when lc.id is not null then map.weight else 0 end),0),2) as evidence_weight
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
