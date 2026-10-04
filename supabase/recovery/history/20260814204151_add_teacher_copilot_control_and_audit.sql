-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260814204151
create table if not exists public.educator_copilot_requests (
  id uuid primary key default gen_random_uuid(),
  educator_id uuid not null references public.educator_profiles(user_id) on delete cascade,
  classroom_id uuid references public.educator_classrooms(id) on delete set null,
  mode text not null check(mode in ('lesson_plan','worksheet','explain','differentiation','intervention')),
  language_code text not null check(language_code in ('en','am','om','ti','so')),
  model text not null,
  prompt_chars integer not null default 0,
  created_at timestamptz not null default now()
);
alter table public.educator_copilot_requests enable row level security;
create index if not exists educator_copilot_requests_user_day_idx on public.educator_copilot_requests(educator_id,created_at desc);
drop policy if exists educator_copilot_self on public.educator_copilot_requests;
create policy educator_copilot_self on public.educator_copilot_requests for select to authenticated using (educator_id=(select auth.uid()) or private.is_admin_user());
drop policy if exists mela_master_gate on public.educator_copilot_requests;
create policy mela_master_gate on public.educator_copilot_requests as restrictive for all to anon,authenticated using (public.platform_feature_available('platform_live') or private.is_admin_user()) with check (public.platform_feature_available('platform_live') or private.is_admin_user());
grant select on public.educator_copilot_requests to authenticated;grant select,insert,update,delete on public.educator_copilot_requests to service_role;
insert into public.platform_feature_flags(feature_key,label,description,enabled,config,updated_at) values('teacher_copilot','Teacher Copilot','AI planning assistant for verified educators. Uses aggregate classroom mastery data and does not send student names to the AI provider.',true,jsonb_build_object('daily_limit',50,'verified_educator_only',true,'no_student_pii_to_ai',true),now()) on conflict(feature_key) do update set label=excluded.label,description=excluded.description,config=excluded.config,updated_at=now();
;
