-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812214422
alter table public.ai_coach_sessions add column if not exists language text not null default 'English';
create index if not exists ai_coach_sessions_user_updated_idx on public.ai_coach_sessions(user_id,updated_at desc);

-- Client users may read their legacy tutor sessions, but the server function owns transcript writes.
revoke insert,update,delete on public.ai_coach_sessions from authenticated,anon;
grant select on public.ai_coach_sessions to authenticated;
revoke insert,update,delete on public.ai_tutor_usage from authenticated,anon;
grant select on public.ai_tutor_usage to authenticated;

;
