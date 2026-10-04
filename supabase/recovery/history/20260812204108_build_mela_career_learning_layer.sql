-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812204108
alter table public.path_modules
  add column if not exists description text,
  add column if not exists estimated_minutes integer not null default 120,
  add column if not exists learning_outcomes jsonb not null default '[]'::jsonb;

create table if not exists public.path_lessons (
  id uuid primary key default gen_random_uuid(),
  module_id uuid not null references public.path_modules(id) on delete cascade,
  lesson_order integer not null,
  title text not null,
  slug text,
  lesson_type text not null default 'lesson',
  summary text not null,
  content_markdown text not null,
  learning_objectives jsonb not null default '[]'::jsonb,
  key_points jsonb not null default '[]'::jsonb,
  practical_activity text,
  reflection_question text,
  estimated_minutes integer not null default 25,
  is_published boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint path_lessons_order_chk check (lesson_order > 0),
  constraint path_lessons_minutes_chk check (estimated_minutes between 5 and 180),
  constraint path_lessons_type_chk check (lesson_type in ('lesson','practice','review','assessment_prep')),
  constraint path_lessons_module_order_key unique (module_id, lesson_order)
);

create table if not exists public.path_lesson_translations (
  id uuid primary key default gen_random_uuid(),
  lesson_id uuid not null references public.path_lessons(id) on delete cascade,
  language_code text not null,
  title text not null,
  summary text not null,
  content_markdown text not null,
  learning_objectives jsonb not null default '[]'::jsonb,
  key_points jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint path_lesson_translations_language_chk check (language_code in ('en','am','om','ti','so')),
  constraint path_lesson_translations_lesson_language_key unique (lesson_id, language_code)
);

create table if not exists public.path_module_resources (
  id uuid primary key default gen_random_uuid(),
  module_id uuid not null references public.path_modules(id) on delete cascade,
  resource_order integer not null default 1,
  resource_type text not null default 'worksheet',
  title text not null,
  description text not null,
  content_markdown text not null,
  language_code text not null default 'en',
  is_published boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint path_module_resources_order_chk check (resource_order > 0),
  constraint path_module_resources_type_chk check (resource_type in ('worksheet','checklist','template','reference','case_study')),
  constraint path_module_resources_language_chk check (language_code in ('en','am','om','ti','so')),
  constraint path_module_resources_module_order_language_key unique (module_id, resource_order, language_code)
);

create table if not exists public.student_lesson_progress (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  lesson_id uuid not null references public.path_lessons(id) on delete cascade,
  status text not null default 'not_started',
  progress_percent integer not null default 0,
  time_spent_seconds integer not null default 0,
  started_at timestamptz,
  completed_at timestamptz,
  last_viewed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint student_lesson_progress_status_chk check (status in ('not_started','in_progress','completed')),
  constraint student_lesson_progress_pct_chk check (progress_percent between 0 and 100),
  constraint student_lesson_progress_time_chk check (time_spent_seconds >= 0),
  constraint student_lesson_progress_user_lesson_key unique (user_id, lesson_id)
);

create index if not exists path_lessons_module_idx on public.path_lessons(module_id, lesson_order);
create index if not exists path_lesson_translations_lesson_idx on public.path_lesson_translations(lesson_id, language_code);
create index if not exists path_module_resources_module_idx on public.path_module_resources(module_id, resource_order);
create index if not exists student_lesson_progress_user_idx on public.student_lesson_progress(user_id, last_viewed_at desc);
create index if not exists student_lesson_progress_lesson_idx on public.student_lesson_progress(lesson_id);

alter table public.path_lessons enable row level security;
alter table public.path_lesson_translations enable row level security;
alter table public.path_module_resources enable row level security;
alter table public.student_lesson_progress enable row level security;

drop policy if exists "Published path lessons readable" on public.path_lessons;
create policy "Published path lessons readable" on public.path_lessons for select to anon, authenticated using (is_published = true);

drop policy if exists "Published lesson translations readable" on public.path_lesson_translations;
create policy "Published lesson translations readable" on public.path_lesson_translations for select to anon, authenticated using (exists (select 1 from public.path_lessons pl where pl.id = lesson_id and pl.is_published = true));

drop policy if exists "Published module resources readable" on public.path_module_resources;
create policy "Published module resources readable" on public.path_module_resources for select to anon, authenticated using (is_published = true);

drop policy if exists "Students view own lesson progress" on public.student_lesson_progress;
create policy "Students view own lesson progress" on public.student_lesson_progress for select to authenticated using ((select auth.uid()) = user_id);

drop policy if exists "Students create own lesson progress" on public.student_lesson_progress;
create policy "Students create own lesson progress" on public.student_lesson_progress for insert to authenticated with check ((select auth.uid()) = user_id and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'student'::public.user_role));

drop policy if exists "Students update own lesson progress" on public.student_lesson_progress;
create policy "Students update own lesson progress" on public.student_lesson_progress for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

revoke all on public.path_lessons, public.path_lesson_translations, public.path_module_resources, public.student_lesson_progress from anon, authenticated;
grant select on public.path_lessons, public.path_lesson_translations, public.path_module_resources to anon, authenticated;
grant select, insert, update on public.student_lesson_progress to authenticated;
grant all on public.path_lessons, public.path_lesson_translations, public.path_module_resources, public.student_lesson_progress to service_role;
;
