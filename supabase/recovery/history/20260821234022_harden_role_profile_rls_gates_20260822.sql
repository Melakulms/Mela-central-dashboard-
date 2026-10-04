-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260821234022
begin;

-- Remove feature-flag/live ALL policies from role-specific profile tables.
drop policy if exists mela_verified_active_gate_v35 on public.company_profiles;
drop policy if exists mela_master_gate on public.educator_profiles;
drop policy if exists mela_gate_mentorship on public.mentor_profiles;
drop policy if exists mela_gate_platform_live on public.mentor_profiles;
drop policy if exists mela_verified_active_gate_v35 on public.parent_profiles;
drop policy if exists mela_verified_active_gate_v35 on public.student_profiles;
drop policy if exists mela_verified_active_gate_v35 on public.teacher_profiles;

-- Private role profiles must not be directly reachable by anonymous clients.
revoke all on table public.company_profiles from anon;
revoke all on table public.educator_profiles from anon;
revoke all on table public.parent_profiles from anon;
revoke all on table public.student_profiles from anon;
revoke all on table public.teacher_profiles from anon;

-- Mentor discovery intentionally retains anonymous SELECT through its explicit
-- verified/active public-read policy; no anonymous writes are permitted.
revoke insert, update, delete on table public.mentor_profiles from anon;

commit;
;
