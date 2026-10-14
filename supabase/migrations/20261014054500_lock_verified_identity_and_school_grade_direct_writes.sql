-- Prevent clients from changing verified identity fields or student grade/stage
-- directly. Previously authenticated clients held column-level UPDATE grants
-- on profiles.email, phone_number, education_stage_key, grade_level and
-- onboarding_step, bypassing stage corrections enforced by the official RPC.
--
-- The supported education/profile mutations use postgres-owned SECURITY
-- DEFINER functions, so revoking direct browser writes does not affect them.
-- Preferred language, contact and non-trust display fields remain editable.
revoke update (email, phone_number, education_stage_key, grade_level, onboarding_step)
  on table public.profiles from anon, authenticated;
