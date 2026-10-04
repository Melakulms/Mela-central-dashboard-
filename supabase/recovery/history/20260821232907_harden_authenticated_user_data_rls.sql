-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260821232907
drop policy if exists mela_gate_platform_live on public.lesson_progress;
drop policy if exists mela_gate_platform_live on public.student_lesson_progress;
drop policy if exists mela_gate_platform_live on public.student_module_progress;
drop policy if exists mela_verified_active_gate_v35 on public.lesson_progress;
drop policy if exists mela_verified_active_gate_v35 on public.student_lesson_progress;
drop policy if exists mela_verified_active_gate_v35 on public.student_module_progress;
drop policy if exists mela_gate_platform_live on public.payments;
drop policy if exists mela_verified_active_gate_v35 on public.payments;
drop policy if exists mela_gate_platform_live on public.user_subscriptions;
drop policy if exists mela_verified_active_gate_v35 on public.user_subscriptions;
drop policy if exists mela_gate_platform_live on public.earnings_ledger;
drop policy if exists mela_verified_active_gate_v35 on public.earnings_ledger;
drop policy if exists mela_gate_platform_live on public.profiles;

;
