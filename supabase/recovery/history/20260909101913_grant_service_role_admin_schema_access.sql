-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260909101913

-- Critical bug: service_role (used by mela-admin-api and mela-ai-admin Edge
-- Functions) had ZERO grants on the entire `admin` schema. The admin schema's
-- own bootstrap migration revoked all access from public/anon/authenticated
-- but never explicitly granted anything to service_role -- unlike the default
-- `public` schema, custom schemas don't get Supabase's automatic service_role
-- grants. Confirmed by reproduction: the literal first query mela-admin-api
-- runs on every request (checking admin.admin_users to see if the caller is
-- an active admin) fails with "permission denied for table admin_users" under
-- a real service_role connection. This means the entire admin dashboard
-- backend has never successfully completed a single request -- every action
-- (dashboard, users, employers, opportunities, payments, moderation, settings,
-- commissions, authorization, audit) would fail before even reaching its own
-- logic. All existing seed data (bootstrap admin, roles, permissions, audit
-- entries) was created via direct migration, not through the deployed app.

GRANT USAGE ON SCHEMA admin TO service_role;

GRANT SELECT ON admin.admin_users TO service_role;
GRANT SELECT ON admin.roles TO service_role;
GRANT SELECT ON admin.role_permissions TO service_role;
GRANT SELECT ON admin.permissions TO service_role;
GRANT SELECT ON admin.access_requests TO service_role;
GRANT SELECT, INSERT ON admin.audit_log TO service_role;

;
