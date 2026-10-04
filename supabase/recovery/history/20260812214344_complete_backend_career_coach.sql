-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812214344
-- Secure Career Coach persistence and usage controls.

create table if not exists public.career_coach_usage (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  session_id uuid references public.career_coach_sessions(id) on delete set null,
  model text not null,
  input_chars integer not null default 0 check (input_chars>=0),
  output_chars integer not null default 0 check (output_chars>=0),
  created_at timestamptz not null default now()
);
alter table public.career_coach_usage enable row level security;
create index if not exists career_coach_usage_user_created_idx on public.career_coach_usage(user_id,created_at desc);
create policy "Career coach usage owner read" on public.career_coach_usage for select to authenticated
using (user_id=(select auth.uid()) or private.is_admin_user());
grant select on public.career_coach_usage to authenticated;
revoke insert,update,delete on public.career_coach_usage from authenticated,anon;

-- Messages are written by the server function only, preventing users from impersonating assistant output.
drop policy if exists "Users add coach messages" on public.career_coach_messages;
revoke insert,update,delete on public.career_coach_messages from authenticated,anon;
grant select on public.career_coach_messages to authenticated;

-- Users may create/read/delete sessions; only goal/title are user editable. Summary is server maintained.
revoke insert,update on public.career_coach_sessions from authenticated;
grant insert (user_id,title,career_goal) on public.career_coach_sessions to authenticated;
grant update (title,career_goal) on public.career_coach_sessions to authenticated;

create or replace function private.touch_career_coach_session()
returns trigger language plpgsql set search_path='pg_catalog','public' as $$
begin new.updated_at=now(); return new; end;$$;
drop trigger if exists trg_touch_career_coach_session on public.career_coach_sessions;
create trigger trg_touch_career_coach_session before update on public.career_coach_sessions
for each row execute function private.touch_career_coach_session();

-- Basic retention metadata for privacy/operations.
alter table public.career_coach_sessions add column if not exists archived_at timestamptz;
alter table public.career_coach_sessions add column if not exists last_message_at timestamptz;
create index if not exists career_coach_sessions_user_updated_idx on public.career_coach_sessions(user_id,updated_at desc);
create index if not exists career_coach_messages_session_created_idx on public.career_coach_messages(session_id,created_at);

;
