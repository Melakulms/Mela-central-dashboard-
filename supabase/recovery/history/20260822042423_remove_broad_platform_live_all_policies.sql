-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260822042423
drop policy if exists "mela_gate_platform_live" on public.admin_audit_logs;
drop policy if exists "mela_gate_career_passport" on public.user_badges;
drop policy if exists "mela_gate_platform_live" on public.user_badges;
drop policy if exists "mela_gate_career_passport" on public.verified_skills;
drop policy if exists "mela_gate_platform_live" on public.verified_skills;
drop policy if exists "mela_gate_platform_live" on public.badges;
drop policy if exists "mela_gate_platform_live" on public.work_reputation;
drop policy if exists "mela_gate_earn_work" on public.work_reviews;
drop policy if exists "mela_gate_platform_live" on public.work_reviews;
drop policy if exists "mela_gate_earn_work" on public.work_reputation;
;
