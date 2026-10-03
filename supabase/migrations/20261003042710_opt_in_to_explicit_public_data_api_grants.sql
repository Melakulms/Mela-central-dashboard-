-- Opt in early to Supabase's explicit Data API grants model for new public objects.
-- Existing objects keep their current grants; future public tables/sequences require reviewed grants.
alter default privileges for role postgres in schema public
revoke select, insert, update, delete on tables from anon, authenticated, service_role;

alter default privileges for role postgres in schema public
revoke usage, select on sequences from anon, authenticated, service_role;
