-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260809180848
alter table public.ai_coach_sessions add column if not exists course_id uuid references public.courses(id) on delete cascade;
alter table public.ai_coach_sessions add column if not exists lesson_id uuid references public.course_lessons(id) on delete set null;
alter table public.ai_coach_sessions add column if not exists language public.app_language not null default 'en';
alter table public.ai_coach_sessions add column if not exists updated_at timestamptz not null default now();

alter table public.ai_coach_sessions enable row level security;
drop policy if exists "ai_coach: self manage" on public.ai_coach_sessions;
drop policy if exists ai_coach_self_read on public.ai_coach_sessions;
create policy ai_coach_self_read on public.ai_coach_sessions for select to authenticated using ((select auth.uid()) = user_id);
revoke all on public.ai_coach_sessions from anon, authenticated;
grant select on public.ai_coach_sessions to authenticated;

create table if not exists public.ai_tutor_usage (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  session_id uuid references public.ai_coach_sessions(id) on delete set null,
  course_id uuid not null references public.courses(id) on delete cascade,
  model text not null,
  input_chars integer not null default 0 check (input_chars >= 0),
  output_chars integer not null default 0 check (output_chars >= 0),
  created_at timestamptz not null default now()
);
alter table public.ai_tutor_usage enable row level security;
drop policy if exists ai_tutor_usage_self_read on public.ai_tutor_usage;
create policy ai_tutor_usage_self_read on public.ai_tutor_usage for select to authenticated using ((select auth.uid()) = user_id);
revoke all on public.ai_tutor_usage from anon, authenticated;
grant select on public.ai_tutor_usage to authenticated;
create index if not exists ai_tutor_usage_user_created_idx on public.ai_tutor_usage(user_id, created_at desc);
create index if not exists ai_coach_sessions_user_updated_idx on public.ai_coach_sessions(user_id, updated_at desc);

;
