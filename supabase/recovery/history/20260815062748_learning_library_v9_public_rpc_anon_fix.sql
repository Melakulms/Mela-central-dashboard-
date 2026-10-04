-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815062748
create or replace function public.get_mela_chapter_library(p_stage_key text,p_grade_level smallint default null,p_track_key text default null)
returns jsonb language sql stable security invoker set search_path to '' as $$
select jsonb_build_object(
 'stage_key',p_stage_key,'grade_level',p_grade_level,'track_key',p_track_key,
 'programs',coalesce((select jsonb_agg(jsonb_build_object(
   'program_key',p.program_key,'subject_key',p.subject_key,'subject_title',p.subject_title,'title',p.title,'description',p.description,
   'program_kind',p.program_kind,'track_key',p.track_key,'grade_level',p.grade_level,'optional',p.optional,'official_alignment_status',p.official_alignment_status,
   'chapters',coalesce((select jsonb_agg(jsonb_build_object(
     'chapter_key',c.chapter_key,'chapter_number',c.chapter_number,'title',c.title,'title_local',c.title_local,'description',c.description,
     'learning_outcomes',c.learning_outcomes,'source_name',c.source_name,'source_url',c.source_url,'source_kind',c.source_kind,
     'source_verified',c.source_verified,'official_alignment_status',c.official_alignment_status,
     'topics',coalesce((select jsonb_agg(jsonb_build_object(
       'topic_key',t.topic_key,'topic_number',t.topic_number,'title',t.title,'title_local',t.title_local,'description',t.description,
       'learning_objectives',t.learning_objectives,'source_verified',t.source_verified
     ) order by t.display_order,t.topic_number) from public.mela_learning_chapter_topics t where t.chapter_id=c.id and t.status='published'),'[]'::jsonb),
     'materials',coalesce((select jsonb_agg(jsonb_build_object(
       'material_key',m.material_key,'topic_id',m.topic_id,'material_type',m.material_type,'title',m.title,'summary',m.summary,
       'pedagogical_role',m.pedagogical_role,'access_tier',m.access_tier,'product_key',m.product_key,'estimated_minutes',m.estimated_minutes,
       'downloadable',m.downloadable,'low_bandwidth_ready',m.low_bandwidth_ready,
       'can_access',case when m.access_tier='free' then true when (select auth.uid()) is null then false
         when m.access_tier='subscription' then exists(
           select 1 from public.mela_user_learning_entitlements e join public.mela_learning_products pr on pr.product_key=e.product_key
           where e.user_id=(select auth.uid()) and e.status='active' and pr.product_type in ('subscription','institution')
             and e.starts_at<=now() and (e.ends_at is null or e.ends_at>now()))
         when m.access_tier='one_time' then exists(
           select 1 from public.mela_user_learning_entitlements e where e.user_id=(select auth.uid()) and e.status='active'
             and e.product_key=m.product_key and e.starts_at<=now() and (e.ends_at is null or e.ends_at>now())) else false end
     ) order by m.display_order,m.title) from public.mela_learning_chapter_materials m where m.chapter_id=c.id and m.status='published'),'[]'::jsonb)
   ) order by c.chapter_number) from public.mela_learning_chapters c where c.program_key=p.program_key and c.status='published'),'[]'::jsonb)
 ) order by p.display_order,p.title) from public.mela_learning_programs p
 where p.active and p.stage_key=p_stage_key and (p_grade_level is null or p.grade_level=p_grade_level) and (p_track_key is null or p.track_key=p_track_key)),'[]'::jsonb),
 'products',coalesce((select jsonb_agg(jsonb_build_object(
    'product_key',x.product_key,'product_name',x.product_name,'product_type',x.product_type,'billing_period',x.billing_period,
    'recommended_price_minor',x.recommended_price_minor,'active_price_minor',x.active_price_minor,'currency',x.currency,
    'description',x.description,'features',x.features,'sale_enabled',x.sale_enabled
  ) order by x.display_order) from public.mela_learning_products x where x.active and (cardinality(x.audience_stage_keys)=0 or p_stage_key=any(x.audience_stage_keys))),'[]'::jsonb)
);
$$;

create or replace function public.get_mela_chapter_material(p_material_key text)
returns jsonb language sql stable security invoker set search_path to '' as $$
select jsonb_build_object(
 'material_key',m.material_key,'title',m.title,'summary',m.summary,'material_type',m.material_type,'access_tier',m.access_tier,'product_key',m.product_key,
 'subject_title',p.subject_title,'grade_level',p.grade_level,'stage_key',p.stage_key,'track_key',p.track_key,'program_title',p.title,
 'chapter_key',c.chapter_key,'chapter_number',c.chapter_number,'chapter_title',c.title,'chapter_title_local',c.title_local,
 'official_alignment_status',c.official_alignment_status,'source_name',c.source_name,'source_url',c.source_url,'source_kind',c.source_kind,'source_verified',c.source_verified,
 'content_markdown',mc.content_markdown,'answer_key','[]'::jsonb,'locked',mc.material_id is null
)
from public.mela_learning_chapter_materials m
join public.mela_learning_chapters c on c.id=m.chapter_id
join public.mela_learning_programs p on p.program_key=c.program_key
left join public.mela_learning_chapter_material_content mc on mc.material_id=m.id
where m.material_key=p_material_key and m.status='published';
$$;

revoke all on function public.get_mela_chapter_library(text,smallint,text),public.get_mela_chapter_material(text) from public;
grant execute on function public.get_mela_chapter_library(text,smallint,text),public.get_mela_chapter_material(text) to anon,authenticated,service_role;
;
