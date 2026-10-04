-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260825184905
REVOKE EXECUTE ON FUNCTION private.guard_user_subscription_state() FROM PUBLIC, anon, authenticated;
;
