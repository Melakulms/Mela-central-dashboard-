-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260825180539
revoke execute on function private.protect_matching_config_audit() from public, anon, authenticated;
revoke execute on function private.guard_profile_role_trust_fields() from public, anon, authenticated;
revoke execute on function private.guard_role_specific_profile_fields() from public, anon, authenticated;
revoke execute on function private.guard_educator_classroom_role() from public, anon, authenticated;
revoke execute on function private.protect_role_specific_profile_identity() from public, anon, authenticated;
revoke execute on function public.guard_role_profile_verification_fields() from public, anon, authenticated;
;
