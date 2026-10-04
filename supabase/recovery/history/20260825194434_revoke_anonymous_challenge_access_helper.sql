-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260825194434
REVOKE EXECUTE ON FUNCTION private.has_challenge_manage_access(uuid) FROM anon;
;
