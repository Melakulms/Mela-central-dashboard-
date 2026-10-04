-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260825185912
REVOKE EXECUTE ON FUNCTION private.guard_profile_sensitive_updates() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION private.guard_profile_verification_fields() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION private.protect_profile_identity_fields() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION private.sync_auth_user_profile() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION private.sync_profile_education_stage() FROM PUBLIC, anon, authenticated;
;
