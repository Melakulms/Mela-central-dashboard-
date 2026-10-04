-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260821234310
drop policy if exists mela_gate_platform_live on public.employers; drop policy if exists mela_verified_active_gate_v35 on public.employers; drop policy if exists mela_gate_opportunities on public.opportunities; drop policy if exists mela_gate_platform_live on public.opportunities; drop policy if exists mela_verified_active_gate_v35 on public.opportunities;
;
