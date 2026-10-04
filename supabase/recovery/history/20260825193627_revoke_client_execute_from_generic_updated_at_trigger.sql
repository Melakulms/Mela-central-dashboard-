-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260825193627
REVOKE EXECUTE ON FUNCTION private.set_generic_updated_at() FROM PUBLIC, anon, authenticated;
;
