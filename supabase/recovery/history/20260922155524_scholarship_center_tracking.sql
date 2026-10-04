-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260922155524
create table if not exists public.scholarship_saved (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  opportunity_id uuid not null references public.opportunities(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique(user_id, opportunity_id)
);

create table if not exists public.scholarship_application_tasks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  opportunity_id uuid not null references public.opportunities(id) on delete cascade,
  application_id uuid null references public.applications(id) on delete cascade,
  title text not null,
  task_type text not null default 'requirement',
  due_at timestamptz null,
  completed boolean not null default false,
  completed_at timestamptz null,
  created_at timestamptz not null default now(),
  unique(user_id, opportunity_id, title)
);

alter table public.scholarship_saved enable row level security;
alter table public.scholarship_application_tasks enable row level security;

drop policy if exists scholarship_saved_self on public.scholarship_saved;
create policy scholarship_saved_self on public.scholarship_saved for all to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

drop policy if exists scholarship_tasks_self on public.scholarship_application_tasks;
create policy scholarship_tasks_self on public.scholarship_application_tasks for all to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

create index if not exists scholarship_saved_user_idx on public.scholarship_saved(user_id, created_at desc);
create index if not exists scholarship_tasks_user_idx on public.scholarship_application_tasks(user_id, completed, due_at);
;
