-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260825185224
REVOKE EXECUTE ON FUNCTION private.prevent_payment_identity_change() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION private.touch_payment_updated_at() FROM PUBLIC, anon, authenticated;
;
