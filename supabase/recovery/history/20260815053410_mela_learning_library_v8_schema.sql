-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815053410
create table if not exists public.mela_learning_products (
  product_key text primary key,
  product_name text not null,
  product_type text not null check (product_type in ('free','subscription','one_time','institution')),
  billing_period text not null check (billing_period in ('none','monthly','annual','one_time','custom')),
  recommended_price_minor integer not null default 0 check (recommended_price_minor >= 0),
  active_price_minor integer check (active_price_minor is null or active_price_minor >= 0),
  currency text not null default 'ETB',
  audience_stage_keys text[] not null default '{}',
  description text not null,
  features jsonb not null default '[]'::jsonb,
  sale_enabled boolean not null default false,
  active boolean not null default true,
  display_order smallint not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.mela_learning_programs (
  program_key text primary key,
  stage_key text not null,
  grade_level smallint,
  track_key text not null default 'common',
  subject_key text not null,
  subject_title text not null,
  title text not null,
  description text not null,
  program_kind text not null default 'school_subject' check (program_kind in ('school_subject','tvet_foundation','tvet_pathway','university_foundation','university_pathway','exam_prep','professional')),
  official_alignment_status text not null default 'supplemental_pending_official_mapping',
  source_name text,
  source_url text,
  optional boolean not null default false,
  active boolean not null default true,
  display_order integer not null default 100,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (grade_level is null or grade_level between 1 and 12)
);

create table if not exists public.mela_learning_units (
  id uuid primary key default gen_random_uuid(),
  program_key text not null references public.mela_learning_programs(program_key) on delete cascade,
  unit_number smallint not null check (unit_number >= 1),
  title text not null,
  description text not null,
  learning_outcomes jsonb not null default '[]'::jsonb,
  prerequisite_note text,
  status text not null default 'draft' check (status in ('draft','published','retired')),
  official_alignment_status text not null default 'supplemental_pending_official_mapping',
  estimated_hours numeric not null default 3 check (estimated_hours > 0),
  display_order integer not null default 100,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(program_key,unit_number)
);

create table if not exists public.mela_learning_materials (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.mela_learning_units(id) on delete cascade,
  material_key text not null unique,
  material_type text not null check (material_type in ('core_lesson','lesson_summary','worked_examples','guided_practice','mastery_practice','quiz','flashcards','worksheet','project','lab','simulation','revision_pack','mock_exam','teacher_guide','parent_guide','study_plan','reference','video_link')),
  title text not null,
  summary text not null,
  pedagogical_role text not null default 'teach' check (pedagogical_role in ('teach','practice','assess','apply','revise','support','reference')),
  language_code text not null default 'en' check (language_code in ('en','am','om','ti','so')),
  access_tier text not null default 'free' check (access_tier in ('free','subscription','one_time')),
  product_key text references public.mela_learning_products(product_key) on delete restrict,
  estimated_minutes integer not null default 20 check (estimated_minutes > 0),
  downloadable boolean not null default true,
  low_bandwidth_ready boolean not null default true,
  status text not null default 'draft' check (status in ('draft','published','retired')),
  editorial_status text not null default 'mela_supplemental' check (editorial_status in ('mela_supplemental','educator_reviewed','officially_mapped','retired')),
  display_order integer not null default 100,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((access_tier='one_time' and product_key is not null) or access_tier<>'one_time')
);

create table if not exists public.mela_learning_material_content (
  material_id uuid primary key references public.mela_learning_materials(id) on delete cascade,
  content_markdown text not null,
  answer_key jsonb not null default '[]'::jsonb,
  source_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.mela_learning_material_translations (
  id uuid primary key default gen_random_uuid(),
  material_id uuid not null references public.mela_learning_materials(id) on delete cascade,
  language_code text not null check (language_code in ('am','om','ti','so')),
  translated_title text,
  translated_summary text,
  content_markdown text,
  review_status text not null default 'pending' check (review_status in ('pending','machine_draft','human_review','certified','rejected')),
  reviewer_note text,
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(material_id,language_code)
);

create table if not exists public.mela_user_learning_entitlements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  product_key text not null references public.mela_learning_products(product_key) on delete restrict,
  status text not null default 'active' check (status in ('active','expired','cancelled','revoked')),
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  source text not null default 'admin' check (source in ('payment','admin','promotion','institution','migration')),
  source_reference text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at is null or ends_at > starts_at)
);

create index if not exists mela_learning_programs_stage_grade_idx on public.mela_learning_programs(stage_key,grade_level,track_key,display_order);
create index if not exists mela_learning_programs_subject_idx on public.mela_learning_programs(subject_key,grade_level);
create index if not exists mela_learning_units_program_idx on public.mela_learning_units(program_key,unit_number);
create index if not exists mela_learning_materials_unit_idx on public.mela_learning_materials(unit_id,display_order);
create index if not exists mela_learning_materials_access_idx on public.mela_learning_materials(access_tier,status);
create index if not exists mela_learning_material_translations_material_idx on public.mela_learning_material_translations(material_id,language_code);
create index if not exists mela_user_learning_entitlements_user_idx on public.mela_user_learning_entitlements(user_id,status,ends_at);
create index if not exists mela_user_learning_entitlements_product_idx on public.mela_user_learning_entitlements(product_key,status);

alter table public.mela_learning_products enable row level security;
alter table public.mela_learning_programs enable row level security;
alter table public.mela_learning_units enable row level security;
alter table public.mela_learning_materials enable row level security;
alter table public.mela_learning_material_content enable row level security;
alter table public.mela_learning_material_translations enable row level security;
alter table public.mela_user_learning_entitlements enable row level security;

create policy mela_learning_products_public_read on public.mela_learning_products for select to anon,authenticated using (active);
create policy mela_learning_products_admin_write on public.mela_learning_products for all to authenticated using (private.is_admin_user()) with check (private.is_admin_user());

create policy mela_learning_programs_public_read on public.mela_learning_programs for select to anon,authenticated using (active);
create policy mela_learning_programs_admin_write on public.mela_learning_programs for all to authenticated using (private.is_admin_user()) with check (private.is_admin_user());

create policy mela_learning_units_public_read on public.mela_learning_units for select to anon,authenticated using (status='published');
create policy mela_learning_units_admin_write on public.mela_learning_units for all to authenticated using (private.is_admin_user()) with check (private.is_admin_user());

create policy mela_learning_materials_public_read on public.mela_learning_materials for select to anon,authenticated using (status='published');
create policy mela_learning_materials_admin_write on public.mela_learning_materials for all to authenticated using (private.is_admin_user()) with check (private.is_admin_user());

create policy mela_learning_material_content_anon_free on public.mela_learning_material_content for select to anon using (
  exists(select 1 from public.mela_learning_materials m where m.id=material_id and m.status='published' and m.access_tier='free')
);
create policy mela_learning_material_content_authenticated on public.mela_learning_material_content for select to authenticated using (
  exists(
    select 1 from public.mela_learning_materials m
    where m.id=material_id and m.status='published' and (
      m.access_tier='free'
      or (m.access_tier='subscription' and exists(
        select 1 from public.mela_user_learning_entitlements e
        join public.mela_learning_products p on p.product_key=e.product_key
        where e.user_id=(select auth.uid()) and e.status='active' and p.product_type in ('subscription','institution')
          and e.starts_at<=now() and (e.ends_at is null or e.ends_at>now())
      ))
      or (m.access_tier='one_time' and exists(
        select 1 from public.mela_user_learning_entitlements e
        where e.user_id=(select auth.uid()) and e.status='active' and e.product_key=m.product_key
          and e.starts_at<=now() and (e.ends_at is null or e.ends_at>now())
      ))
    )
  )
);
create policy mela_learning_material_content_admin_write on public.mela_learning_material_content for all to authenticated using (private.is_admin_user()) with check (private.is_admin_user());

create policy mela_learning_material_translations_read on public.mela_learning_material_translations for select to authenticated using (
  review_status='certified' or private.is_admin_user() or reviewed_by=(select auth.uid())
);
create policy mela_learning_material_translations_admin_write on public.mela_learning_material_translations for all to authenticated using (private.is_admin_user()) with check (private.is_admin_user());

create policy mela_user_learning_entitlements_self_read on public.mela_user_learning_entitlements for select to authenticated using (user_id=(select auth.uid()) or private.is_admin_user());
create policy mela_user_learning_entitlements_admin_write on public.mela_user_learning_entitlements for all to authenticated using (private.is_admin_user()) with check (private.is_admin_user());

grant select on public.mela_learning_products, public.mela_learning_programs, public.mela_learning_units, public.mela_learning_materials to anon,authenticated;
grant select on public.mela_learning_material_content to anon,authenticated;
grant select on public.mela_learning_material_translations, public.mela_user_learning_entitlements to authenticated;
grant insert,update,delete on public.mela_learning_products, public.mela_learning_programs, public.mela_learning_units, public.mela_learning_materials, public.mela_learning_material_content, public.mela_learning_material_translations, public.mela_user_learning_entitlements to authenticated;
grant select,insert,update,delete on public.mela_learning_products, public.mela_learning_programs, public.mela_learning_units, public.mela_learning_materials, public.mela_learning_material_content, public.mela_learning_material_translations, public.mela_user_learning_entitlements to service_role;
;
