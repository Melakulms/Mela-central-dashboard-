-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815053705
create or replace function public.get_mela_learning_library(p_stage_key text,p_grade_level smallint default null,p_track_key text default null)
returns jsonb
language sql
stable
security invoker
set search_path to ''
as $$
select jsonb_build_object(
  'stage_key',p_stage_key,
  'grade_level',p_grade_level,
  'track_key',p_track_key,
  'programs',coalesce((
    select jsonb_agg(jsonb_build_object(
      'program_key',p.program_key,'subject_key',p.subject_key,'subject_title',p.subject_title,'title',p.title,'description',p.description,
      'program_kind',p.program_kind,'track_key',p.track_key,'grade_level',p.grade_level,'optional',p.optional,'official_alignment_status',p.official_alignment_status,
      'units',coalesce((select jsonb_agg(jsonb_build_object(
        'id',u.id,'unit_number',u.unit_number,'title',u.title,'description',u.description,'learning_outcomes',u.learning_outcomes,'estimated_hours',u.estimated_hours,
        'materials',coalesce((select jsonb_agg(jsonb_build_object(
          'material_key',m.material_key,'material_type',m.material_type,'title',m.title,'summary',m.summary,'pedagogical_role',m.pedagogical_role,
          'access_tier',m.access_tier,'product_key',m.product_key,'estimated_minutes',m.estimated_minutes,'downloadable',m.downloadable,'low_bandwidth_ready',m.low_bandwidth_ready,
          'can_access',case
            when m.access_tier='free' then true
            when (select auth.uid()) is null then false
            when m.access_tier='subscription' then exists(
              select 1 from public.mela_user_learning_entitlements e join public.mela_learning_products pr on pr.product_key=e.product_key
              where e.user_id=(select auth.uid()) and e.status='active' and pr.product_type in ('subscription','institution') and e.starts_at<=now() and (e.ends_at is null or e.ends_at>now())
            ) or private.is_admin_user()
            when m.access_tier='one_time' then exists(
              select 1 from public.mela_user_learning_entitlements e where e.user_id=(select auth.uid()) and e.status='active' and e.product_key=m.product_key and e.starts_at<=now() and (e.ends_at is null or e.ends_at>now())
            ) or private.is_admin_user()
            else false end
        ) order by m.display_order,m.title) from public.mela_learning_materials m where m.unit_id=u.id and m.status='published'),'[]'::jsonb)
      ) order by u.unit_number) from public.mela_learning_units u where u.program_key=p.program_key and u.status='published'),'[]'::jsonb)
    ) order by p.display_order,p.title)
    from public.mela_learning_programs p
    where p.active and p.stage_key=p_stage_key
      and (p_grade_level is null or p.grade_level=p_grade_level)
      and (p_track_key is null or p.track_key=p_track_key)
  ),'[]'::jsonb),
  'products',coalesce((select jsonb_agg(jsonb_build_object(
    'product_key',x.product_key,'product_name',x.product_name,'product_type',x.product_type,'billing_period',x.billing_period,
    'recommended_price_minor',x.recommended_price_minor,'active_price_minor',x.active_price_minor,'currency',x.currency,'description',x.description,
    'features',x.features,'sale_enabled',x.sale_enabled
  ) order by x.display_order) from public.mela_learning_products x where x.active and (cardinality(x.audience_stage_keys)=0 or p_stage_key=any(x.audience_stage_keys))),'[]'::jsonb)
);
$$;

revoke all on function public.get_mela_learning_library(text,smallint,text) from public;
grant execute on function public.get_mela_learning_library(text,smallint,text) to anon,authenticated,service_role;

create or replace function public.get_mela_learning_material(p_material_key text)
returns jsonb
language sql
stable
security invoker
set search_path to ''
as $$
select jsonb_build_object(
  'material_key',m.material_key,'title',m.title,'summary',m.summary,'material_type',m.material_type,'access_tier',m.access_tier,'product_key',m.product_key,
  'subject_title',p.subject_title,'grade_level',p.grade_level,'stage_key',p.stage_key,'track_key',p.track_key,'program_title',p.title,'unit_title',u.title,
  'official_alignment_status',u.official_alignment_status,
  'content_markdown',c.content_markdown,'answer_key',c.answer_key,
  'locked',c.material_id is null
)
from public.mela_learning_materials m
join public.mela_learning_units u on u.id=m.unit_id
join public.mela_learning_programs p on p.program_key=u.program_key
left join public.mela_learning_material_content c on c.material_id=m.id
where m.material_key=p_material_key and m.status='published';
$$;

revoke all on function public.get_mela_learning_material(text) from public;
grant execute on function public.get_mela_learning_material(text) to anon,authenticated,service_role;

create or replace function public.get_my_learning_entitlements()
returns jsonb
language sql
stable
security invoker
set search_path to ''
as $$
select coalesce(jsonb_agg(jsonb_build_object(
  'product_key',e.product_key,'product_name',p.product_name,'product_type',p.product_type,'status',e.status,'starts_at',e.starts_at,'ends_at',e.ends_at,'source',e.source
) order by e.created_at desc),'[]'::jsonb)
from public.mela_user_learning_entitlements e
join public.mela_learning_products p on p.product_key=e.product_key
where e.user_id=(select auth.uid());
$$;

revoke all on function public.get_my_learning_entitlements() from public,anon;
grant execute on function public.get_my_learning_entitlements() to authenticated,service_role;
;
