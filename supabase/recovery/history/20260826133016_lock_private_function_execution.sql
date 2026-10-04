-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260826133016
REVOKE USAGE ON SCHEMA private FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA private FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON ALL PROCEDURES IN SCHEMA private FROM PUBLIC, anon, authenticated;
;
