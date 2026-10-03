-- Future public functions must receive an explicit reviewed EXECUTE grant.
-- This does not change grants on existing RPCs.
alter default privileges for role postgres in schema public
revoke execute on functions from public, anon, authenticated, service_role;
