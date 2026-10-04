-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20261003042756
alter default privileges for role postgres in schema public
revoke execute on functions from public, anon, authenticated, service_role;
;
