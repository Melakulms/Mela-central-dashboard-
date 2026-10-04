-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260814210448
alter table public.education_benchmark_adaptations
add column if not exists outcome_metric_key text references public.mela_outcome_metrics(metric_key) on update cascade on delete set null;
create index if not exists education_benchmark_adaptations_outcome_metric_idx on public.education_benchmark_adaptations(outcome_metric_key);

update public.education_benchmark_adaptations set outcome_metric_key = case country_code
 when 'AU' then 'institution_gap_closure_rate'
 when 'CA' then 'verified_passport_evidence_ratio'
 when 'CH' then 'opportunity_conversion_rate'
 when 'CZ' then 'transition_plan_completion_rate'
 when 'DK' then 'verified_project_rate'
 when 'EE' then 'teacher_intervention_response_hours'
 when 'FI' then 'catchup_completion_rate'
 when 'IE' then 'mastery_growth_90d'
 when 'JP' then 'teacher_intervention_response_hours'
 when 'KR' then 'transition_plan_completion_rate'
 when 'LT' then 'offline_sync_success_rate'
 when 'NL' then 'transition_plan_completion_rate'
 when 'NZ' then 'verified_project_rate'
 when 'PL' then 'mastery_growth_90d'
 when 'PT' then 'family_engagement_rate'
 when 'SE' then 'family_engagement_rate'
 when 'SG' then 'mastery_growth_90d'
 when 'SI' then 'verified_passport_evidence_ratio'
 when 'UY' then 'offline_sync_success_rate'
 when 'VN' then 'foundational_gap_rate'
 else outcome_metric_key end
where active;

create or replace function public.get_mela_education_blueprint()
returns jsonb language sql stable set search_path=''
as $$
select jsonb_build_object(
  'version','2026.08-benchmark-v2',
  'benchmark_country_count',(select count(*) from public.education_benchmark_systems where active),
  'source_practice_count',(select count(*) from public.education_benchmark_practices where active),
  'adaptation_count',(select count(*) from public.education_benchmark_adaptations where active),
  'stages',coalesce((select jsonb_agg(to_jsonb(s) order by s.display_order) from public.education_audience_stages s),'[]'::jsonb),
  'languages',coalesce((select jsonb_agg(jsonb_build_object('code',l.language_code,'name',l.language_name,'native_name',l.native_name,'enabled',l.enabled) order by l.sort_order) from public.platform_languages l where l.enabled),'[]'::jsonb),
  'engines',coalesce((select jsonb_agg(to_jsonb(e) order by e.display_order) from public.mela_education_engines e),'[]'::jsonb),
  'benchmarks',coalesce((select jsonb_agg(to_jsonb(b) order by b.country_name) from public.education_benchmark_systems b where b.active),'[]'::jsonb),
  'source_practices',coalesce((select jsonb_agg(to_jsonb(p) order by p.priority,p.country_code) from public.education_benchmark_practices p where p.active),'[]'::jsonb),
  'mela_adaptations',coalesce((select jsonb_agg(jsonb_build_object(
      'id',a.id,'country_code',a.country_code,'country_name',b.country_name,'engine_key',a.engine_key,
      'practice_key',a.practice_key,'source_practice_key',a.source_practice_key,'source_practice',a.source_practice,
      'mela_adaptation',a.mela_adaptation,'target_stages',a.target_stages,'product_surface',a.product_surface,
      'success_metric',a.success_metric,'outcome_metric_key',a.outcome_metric_key,'priority',a.priority,
      'implementation_status',a.implementation_status,'active',a.active
    ) order by a.priority desc,b.country_name)
    from public.education_benchmark_adaptations a join public.education_benchmark_systems b on b.country_code=a.country_code where a.active),'[]'::jsonb),
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
    'benchmark_adaptations',coalesce((select jsonb_agg(jsonb_build_object(
       'country',b.country_name,'engine_key',a.engine_key,'product_surface',a.product_surface,
       'source_practice',a.source_practice,'mela_adaptation',a.mela_adaptation,'success_metric',a.success_metric,
       'outcome_metric_key',a.outcome_metric_key,'implementation_status',a.implementation_status
      ) order by a.priority desc,b.country_name)
      from public.education_benchmark_adaptations a
      join public.education_benchmark_systems b on b.country_code=a.country_code
      where a.active and v_profile.education_stage_key=any(a.target_stages)),'[]'::jsonb),
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
      'source_practices',(select count(*) from public.education_benchmark_practices where active),
      'adaptations',(select count(*) from public.education_benchmark_adaptations where active),
      'adaptation_status',(select coalesce(jsonb_object_agg(implementation_status,cnt),'{}'::jsonb) from (select implementation_status,count(*) cnt from public.education_benchmark_adaptations where active group by implementation_status)s),
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
;
