-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812214423
alter table public.ai_coach_sessions add column if not exists language text not null default 'en';
alter table public.ai_coach_sessions drop constraint if exists ai_coach_sessions_language_chk;
alter table public.ai_coach_sessions add constraint ai_coach_sessions_language_chk check (language in ('en','am','om','ti','so'));
create index if not exists ai_coach_sessions_user_updated_idx on public.ai_coach_sessions(user_id,updated_at desc);
;
