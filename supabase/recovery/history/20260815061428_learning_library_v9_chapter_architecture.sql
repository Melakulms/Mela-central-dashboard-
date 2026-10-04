-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815061428
create table if not exists public.mela_learning_chapters (
  id uuid primary key default gen_random_uuid(),
  program_key text not null references public.mela_learning_programs(program_key) on update cascade on delete cascade,
  chapter_key text not null unique,
  chapter_number smallint not null,
  title text not null,
  title_local text,
  description text not null default '',
  learning_outcomes jsonb not null default '[]'::jsonb,
  source_name text,
  source_url text,
  source_kind text not null default 'mela_supplemental' check (source_kind in ('official_government','official_regional','secondary_textbook_index','mela_supplemental')),
  source_verified boolean not null default false,
  official_alignment_status text not null default 'supplemental_pending_official_mapping',
  status text not null default 'draft' check (status in ('draft','review','published','archived')),
  display_order integer not null default 100,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(program_key,chapter_number)
);

create table if not exists public.mela_learning_chapter_topics (
  id uuid primary key default gen_random_uuid(),
  chapter_id uuid not null references public.mela_learning_chapters(id) on delete cascade,
  topic_key text not null unique,
  topic_number text not null,
  title text not null,
  title_local text,
  description text not null default '',
  learning_objectives jsonb not null default '[]'::jsonb,
  source_verified boolean not null default false,
  status text not null default 'draft' check (status in ('draft','review','published','archived')),
  display_order integer not null default 100,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(chapter_id,topic_number)
);

create table if not exists public.mela_learning_chapter_materials (
  id uuid primary key default gen_random_uuid(),
  chapter_id uuid not null references public.mela_learning_chapters(id) on delete cascade,
  topic_id uuid references public.mela_learning_chapter_topics(id) on delete cascade,
  material_key text not null unique,
  material_type text not null,
  title text not null,
  summary text not null default '',
  pedagogical_role text not null default 'teach',
  language_code text not null default 'en',
  access_tier text not null default 'free' check (access_tier in ('free','subscription','one_time')),
  product_key text references public.mela_learning_products(product_key) on update cascade on delete set null,
  estimated_minutes integer not null default 20 check (estimated_minutes > 0),
  downloadable boolean not null default true,
  low_bandwidth_ready boolean not null default true,
  status text not null default 'draft' check (status in ('draft','review','published','archived')),
  editorial_status text not null default 'mela_supplemental',
  display_order integer not null default 100,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.mela_learning_chapter_material_content (
  material_id uuid primary key references public.mela_learning_chapter_materials(id) on delete cascade,
  content_markdown text not null,
  answer_key jsonb not null default '[]'::jsonb,
  source_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.mela_learning_chapter_material_translations (
  id uuid primary key default gen_random_uuid(),
  material_id uuid not null references public.mela_learning_chapter_materials(id) on delete cascade,
  language_code text not null,
  translated_title text,
  translated_summary text,
  content_markdown text,
  review_status text not null default 'pending' check (review_status in ('pending','in_review','approved','rejected')),
  reviewer_note text,
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(material_id,language_code)
);

create index if not exists mela_learning_chapters_program_idx on public.mela_learning_chapters(program_key,chapter_number);
create index if not exists mela_learning_chapter_topics_chapter_idx on public.mela_learning_chapter_topics(chapter_id,display_order);
create index if not exists mela_learning_chapter_materials_chapter_idx on public.mela_learning_chapter_materials(chapter_id,display_order);
create index if not exists mela_learning_chapter_materials_topic_idx on public.mela_learning_chapter_materials(topic_id);
create index if not exists mela_learning_chapter_materials_product_idx on public.mela_learning_chapter_materials(product_key);
create index if not exists mela_learning_chapter_translations_material_idx on public.mela_learning_chapter_material_translations(material_id,language_code);
create index if not exists mela_learning_chapter_translations_reviewed_idx on public.mela_learning_chapter_material_translations(reviewed_by);

alter table public.mela_learning_chapters enable row level security;
alter table public.mela_learning_chapter_topics enable row level security;
alter table public.mela_learning_chapter_materials enable row level security;
alter table public.mela_learning_chapter_material_content enable row level security;
alter table public.mela_learning_chapter_material_translations enable row level security;

create policy mela_learning_chapters_anon_read on public.mela_learning_chapters for select to anon using (status='published');
create policy mela_learning_chapters_authenticated_read on public.mela_learning_chapters for select to authenticated using (status='published' or private.is_admin_user());
create policy mela_learning_chapters_admin_insert on public.mela_learning_chapters for insert to authenticated with check (private.is_admin_user());
create policy mela_learning_chapters_admin_update on public.mela_learning_chapters for update to authenticated using (private.is_admin_user()) with check (private.is_admin_user());
create policy mela_learning_chapters_admin_delete on public.mela_learning_chapters for delete to authenticated using (private.is_admin_user());

create policy mela_learning_chapter_topics_anon_read on public.mela_learning_chapter_topics for select to anon using (status='published');
create policy mela_learning_chapter_topics_authenticated_read on public.mela_learning_chapter_topics for select to authenticated using (status='published' or private.is_admin_user());
create policy mela_learning_chapter_topics_admin_insert on public.mela_learning_chapter_topics for insert to authenticated with check (private.is_admin_user());
create policy mela_learning_chapter_topics_admin_update on public.mela_learning_chapter_topics for update to authenticated using (private.is_admin_user()) with check (private.is_admin_user());
create policy mela_learning_chapter_topics_admin_delete on public.mela_learning_chapter_topics for delete to authenticated using (private.is_admin_user());

create policy mela_learning_chapter_materials_anon_read on public.mela_learning_chapter_materials for select to anon using (status='published');
create policy mela_learning_chapter_materials_authenticated_read on public.mela_learning_chapter_materials for select to authenticated using (status='published' or private.is_admin_user());
create policy mela_learning_chapter_materials_admin_insert on public.mela_learning_chapter_materials for insert to authenticated with check (private.is_admin_user());
create policy mela_learning_chapter_materials_admin_update on public.mela_learning_chapter_materials for update to authenticated using (private.is_admin_user()) with check (private.is_admin_user());
create policy mela_learning_chapter_materials_admin_delete on public.mela_learning_chapter_materials for delete to authenticated using (private.is_admin_user());

create policy mela_learning_chapter_content_anon_free on public.mela_learning_chapter_material_content for select to anon using (
  exists(select 1 from public.mela_learning_chapter_materials m where m.id=material_id and m.status='published' and m.access_tier='free')
);
create policy mela_learning_chapter_content_authenticated on public.mela_learning_chapter_material_content for select to authenticated using (
  private.is_admin_user() or exists(
    select 1 from public.mela_learning_chapter_materials m where m.id=material_id and m.status='published' and (
      m.access_tier='free' or
      (m.access_tier='subscription' and exists(
        select 1 from public.mela_user_learning_entitlements e join public.mela_learning_products p on p.product_key=e.product_key
        where e.user_id=(select auth.uid()) and e.status='active' and p.product_type in ('subscription','institution')
          and e.starts_at<=now() and (e.ends_at is null or e.ends_at>now())
      )) or
      (m.access_tier='one_time' and exists(
        select 1 from public.mela_user_learning_entitlements e
        where e.user_id=(select auth.uid()) and e.status='active' and e.product_key=m.product_key
          and e.starts_at<=now() and (e.ends_at is null or e.ends_at>now())
      ))
    )
  )
);
create policy mela_learning_chapter_content_admin_insert on public.mela_learning_chapter_material_content for insert to authenticated with check (private.is_admin_user());
create policy mela_learning_chapter_content_admin_update on public.mela_learning_chapter_material_content for update to authenticated using (private.is_admin_user()) with check (private.is_admin_user());
create policy mela_learning_chapter_content_admin_delete on public.mela_learning_chapter_material_content for delete to authenticated using (private.is_admin_user());

create policy mela_learning_chapter_translations_anon_read on public.mela_learning_chapter_material_translations for select to anon using (review_status='approved');
create policy mela_learning_chapter_translations_authenticated_read on public.mela_learning_chapter_material_translations for select to authenticated using (review_status='approved' or private.is_admin_user());
create policy mela_learning_chapter_translations_admin_insert on public.mela_learning_chapter_material_translations for insert to authenticated with check (private.is_admin_user());
create policy mela_learning_chapter_translations_admin_update on public.mela_learning_chapter_material_translations for update to authenticated using (private.is_admin_user()) with check (private.is_admin_user());
create policy mela_learning_chapter_translations_admin_delete on public.mela_learning_chapter_material_translations for delete to authenticated using (private.is_admin_user());

revoke all on public.mela_learning_chapters,public.mela_learning_chapter_topics,public.mela_learning_chapter_materials,public.mela_learning_chapter_material_content,public.mela_learning_chapter_material_translations from public;
grant select on public.mela_learning_chapters,public.mela_learning_chapter_topics,public.mela_learning_chapter_materials,public.mela_learning_chapter_material_content,public.mela_learning_chapter_material_translations to anon,authenticated;
grant insert,update,delete on public.mela_learning_chapters,public.mela_learning_chapter_topics,public.mela_learning_chapter_materials,public.mela_learning_chapter_material_content,public.mela_learning_chapter_material_translations to authenticated;

create or replace function public.get_mela_chapter_library(p_stage_key text,p_grade_level smallint default null,p_track_key text default null)
returns jsonb language sql stable security invoker set search_path to '' as $$
select jsonb_build_object(
 'stage_key',p_stage_key,'grade_level',p_grade_level,'track_key',p_track_key,
 'programs',coalesce((select jsonb_agg(jsonb_build_object(
   'program_key',p.program_key,'subject_key',p.subject_key,'subject_title',p.subject_title,'title',p.title,'track_key',p.track_key,
   'grade_level',p.grade_level,'official_alignment_status',p.official_alignment_status,
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
         when m.access_tier='subscription' then private.is_admin_user() or exists(
           select 1 from public.mela_user_learning_entitlements e join public.mela_learning_products pr on pr.product_key=e.product_key
           where e.user_id=(select auth.uid()) and e.status='active' and pr.product_type in ('subscription','institution')
             and e.starts_at<=now() and (e.ends_at is null or e.ends_at>now()))
         when m.access_tier='one_time' then private.is_admin_user() or exists(
           select 1 from public.mela_user_learning_entitlements e where e.user_id=(select auth.uid()) and e.status='active'
             and e.product_key=m.product_key and e.starts_at<=now() and (e.ends_at is null or e.ends_at>now())) else false end
     ) order by m.display_order,m.title) from public.mela_learning_chapter_materials m where m.chapter_id=c.id and m.status='published'),'[]'::jsonb)
   ) order by c.chapter_number) from public.mela_learning_chapters c where c.program_key=p.program_key and c.status='published'),'[]'::jsonb)
 ) order by p.display_order,p.title) from public.mela_learning_programs p
 where p.active and p.stage_key=p_stage_key and (p_grade_level is null or p.grade_level=p_grade_level) and (p_track_key is null or p.track_key=p_track_key)),'[]'::jsonb)
);
$$;

create or replace function public.get_mela_chapter_material(p_material_key text)
returns jsonb language sql stable security invoker set search_path to '' as $$
select jsonb_build_object(
 'material_key',m.material_key,'title',m.title,'summary',m.summary,'material_type',m.material_type,'access_tier',m.access_tier,'product_key',m.product_key,
 'subject_title',p.subject_title,'grade_level',p.grade_level,'stage_key',p.stage_key,'track_key',p.track_key,'program_title',p.title,
 'chapter_key',c.chapter_key,'chapter_number',c.chapter_number,'chapter_title',c.title,'chapter_title_local',c.title_local,
 'official_alignment_status',c.official_alignment_status,'source_name',c.source_name,'source_url',c.source_url,'source_verified',c.source_verified,
 'content_markdown',mc.content_markdown,'answer_key',mc.answer_key,'locked',mc.material_id is null
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
