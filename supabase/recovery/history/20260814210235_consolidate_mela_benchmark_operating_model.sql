-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260814210235
alter table public.education_benchmark_adaptations
  add column if not exists source_practice_key text;

update public.education_benchmark_adaptations a
set source_practice_key = p.practice_key
from public.education_benchmark_practices p
where p.country_code = a.country_code
  and a.source_practice_key is null;

alter table public.education_benchmark_adaptations
  drop constraint if exists education_benchmark_adaptations_source_practice_key_fkey;
alter table public.education_benchmark_adaptations
  add constraint education_benchmark_adaptations_source_practice_key_fkey
  foreign key (source_practice_key) references public.education_benchmark_practices(practice_key) on delete set null;
create index if not exists education_benchmark_adaptations_source_practice_idx
  on public.education_benchmark_adaptations(source_practice_key);

create index if not exists mela_offline_content_packs_language_idx
  on public.mela_offline_content_packs(language_code);
create index if not exists learner_offline_sync_state_pack_idx
  on public.learner_offline_sync_state(pack_id);

update public.mela_education_engines
set implementation_status='foundation',
    current_assets=jsonb_build_object(
      'content_table','mela_offline_content_packs',
      'sync_table','learner_offline_sync_state',
      'benchmark_layer','education_benchmark_practices + education_benchmark_adaptations',
      'next','author reviewed low-bandwidth packs and client-side offline event queue'
    ),
    updated_at=now()
where engine_key='mela_lite';

drop table if exists public.learning_offline_packs cascade;

create or replace function public.get_mela_benchmark_blueprint_v2()
returns jsonb
language sql
stable
set search_path=''
as $$
select jsonb_build_object(
  'benchmark_country_count',(select count(*) from public.education_benchmark_systems where active),
  'systems',(select coalesce(jsonb_agg(to_jsonb(b) order by b.country_name),'[]'::jsonb) from public.education_benchmark_systems b where b.active),
  'source_practices',(select coalesce(jsonb_agg(to_jsonb(p) order by p.priority,p.country_code),'[]'::jsonb) from public.education_benchmark_practices p where p.active),
  'engines',(select coalesce(jsonb_agg(to_jsonb(e) order by e.display_order),'[]'::jsonb) from public.mela_education_engines e),
  'adaptations',(select coalesce(jsonb_agg(to_jsonb(a) order by a.priority desc,b.country_name),'[]'::jsonb) from public.education_benchmark_adaptations a join public.education_benchmark_systems b on b.country_code=a.country_code where a.active),
  'core_capabilities',(select coalesce(jsonb_agg(to_jsonb(c) order by c.display_order),'[]'::jsonb) from public.mela_core_capabilities c where c.active),
  'learning_cycle',(select coalesce(jsonb_agg(to_jsonb(s) order by s.step_order),'[]'::jsonb) from public.mela_learning_cycle_steps s where s.active),
  'outcome_metrics',(select coalesce(jsonb_agg(to_jsonb(m) order by m.engine_key,m.metric_key),'[]'::jsonb) from public.mela_outcome_metrics m where m.active),
  'offline_model',jsonb_build_object('content_table','mela_offline_content_packs','sync_table','learner_offline_sync_state'),
  'coverage',jsonb_build_object(
    'adaptation_count',(select count(*) from public.education_benchmark_adaptations where active),
    'countries_with_adaptations',(select count(distinct country_code) from public.education_benchmark_adaptations where active),
    'engines_with_adaptations',(select count(distinct engine_key) from public.education_benchmark_adaptations where active),
    'source_practices_linked',(select count(*) from public.education_benchmark_adaptations where active and source_practice_key is not null),
    'outcome_metric_count',(select count(*) from public.mela_outcome_metrics where active)
  )
);
$$;

revoke all on function public.get_mela_benchmark_blueprint_v2() from public;
grant execute on function public.get_mela_benchmark_blueprint_v2() to authenticated, service_role;
;
