-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260822061625
revoke execute on function public.assessment_language_is_certified(uuid,text) from public, anon; revoke execute on function public.has_current_policy_acknowledgement(text) from public, anon;
;
