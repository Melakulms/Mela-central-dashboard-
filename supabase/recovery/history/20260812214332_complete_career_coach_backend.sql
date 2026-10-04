-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812214332
-- Career Coach usage, integrity constraints and operational indexes.

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
create index if not exists career_coach_messages_session_created_idx on public.career_coach_messages(session_id,created_at);
create index if not exists career_coach_sessions_user_updated_idx on public.career_coach_sessions(user_id,updated_at desc);

alter table public.career_coach_messages drop constraint if exists career_coach_messages_role_chk;
alter table public.career_coach_messages add constraint career_coach_messages_role_chk check (role in ('user','assistant','system'));

create or replace function private.touch_career_coach_session()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  update public.career_coach_sessions set updated_at=now() where id=new.session_id;
  return new;
end;
$$;
drop trigger if exists trg_touch_career_coach_session on public.career_coach_messages;
create trigger trg_touch_career_coach_session after insert on public.career_coach_messages for each row execute function private.touch_career_coach_session();

-- Users can see their own metering, but only the trusted backend writes it.
drop policy if exists "Career coach usage owner select" on public.career_coach_usage;
create policy "Career coach usage owner select" on public.career_coach_usage
for select to authenticated using (user_id=(select auth.uid()) or private.is_admin_user());
revoke insert,update,delete on public.career_coach_usage from authenticated;
grant select on public.career_coach_usage to authenticated;
grant all on public.career_coach_usage to service_role;

-- Assistant/system messages are backend-only. Keep user direct inserts constrained by existing RLS and column privileges.
revoke update,delete on public.career_coach_messages from authenticated;
revoke update on public.career_coach_sessions from authenticated;
grant update (title,career_goal) on public.career_coach_sessions to authenticated;

;
