-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260821233136
drop policy if exists "mela_gate_arena" on public.arena_matches;
drop policy if exists "mela_gate_platform_live" on public.arena_matches;
drop policy if exists "mela_gate_arena" on public.arena_tournaments;
drop policy if exists "mela_gate_platform_live" on public.arena_tournaments;
drop policy if exists "mela_gate_assessments" on public.assessment_attempts;
drop policy if exists "mela_gate_platform_live" on public.assessment_attempts;
drop policy if exists "mela_gate_academy" on public.course_enrollments;
drop policy if exists "mela_gate_platform_live" on public.course_enrollments;
drop policy if exists "mela_verified_active_gate_v35" on public.course_enrollments;
drop policy if exists "mela_gate_mentorship" on public.mentorship_sessions;
drop policy if exists "mela_gate_platform_live" on public.mentorship_sessions;
;
