-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260923192439

-- Root cause found by direct reproduction: authenticated had no USAGE on the
-- private schema at all. This didn't surface earlier because most private.*
-- calls go through SECURITY DEFINER public wrappers (running as the definer,
-- not authenticated) -- but protect_opportunity_moderation_v35 is a plain
-- (non-definer) trigger that calls private.is_admin_user() directly, so it
-- runs as the real calling role and hits the schema wall. USAGE alone grants
-- no object access -- every private.* function authenticated can actually
-- call still needs its own EXECUTE grant, applied individually as found.
GRANT USAGE ON SCHEMA private TO authenticated;

;
