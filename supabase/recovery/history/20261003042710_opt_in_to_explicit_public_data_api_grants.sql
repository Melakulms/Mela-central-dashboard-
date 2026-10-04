-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20261003042710
alter default privileges for role postgres in schema public
revoke select, insert, update, delete on tables from anon, authenticated, service_role;

alter default privileges for role postgres in schema public
revoke usage, select on sequences from anon, authenticated, service_role;
;
