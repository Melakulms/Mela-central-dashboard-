-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260822034435
REVOKE EXECUTE ON FUNCTION public.guard_learning_payment_attempt() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.guard_role_profile_verification_fields() FROM PUBLIC, anon, authenticated;
;
