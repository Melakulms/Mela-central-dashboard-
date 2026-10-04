-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260825193524
REVOKE EXECUTE ON FUNCTION public.enforce_employer_review_transition() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.enforce_opportunity_review_transition() FROM PUBLIC, anon, authenticated;
;
