-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260825194444
REVOKE EXECUTE ON FUNCTION private.has_challenge_manage_access(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION private.has_challenge_manage_access(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION private.has_challenge_manage_access(uuid) FROM authenticated;
;
