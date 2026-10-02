# MELA Central Admin Dashboard

Standalone administrative control plane for the MELA platform.

## Implemented foundation

- Separate Vite/React application in its own repository
- Separate admin deployment target
- Shared MELA Supabase project
- Separate admin login entry point
- Fail-closed admin authorization
- Admin role/permission model
- MFA/AAL2 enforcement for privileged access
- Server-side admin authorization Edge Function
- Private `admin` database schema for control-plane metadata
- Access-request model
- Central audit-log model
- Admin API request IDs for traceability
- GitHub CI build check
- SPA routing configuration

## Security architecture

The browser never receives a Supabase service-role key. The browser uses only the publishable key and a normal authenticated user session. Privileged operations go through the `mela-admin-api` Edge Function, which verifies the caller, checks the private admin role/permission tables, requires MFA when configured, and writes audit records for privileged administrative actions.

Administrative sessions are intentionally non-persistent in the browser. This limits token exposure while older deployments share a browser origin with other MELA applications. The production admin application must ultimately be served from a dedicated origin such as `https://admin.mela.app`; a path such as `https://example.com/admin/` is not an origin security boundary.

Legacy database functions that use `private.is_admin_user()` receive only a broad super-admin override. Interactive callers must have an active central `admin.admin_users` membership, use the `super_admin` central role, and satisfy AAL2 when that membership requires MFA. Granular administrative roles must use the permissioned admin API instead of legacy override paths.

## Build order

1. Authorization and access control foundation — implemented
2. Audit logging — schema and API foundation implemented
3. Operational dashboard — implemented foundation
4. User/employer/payment/dispute operations
5. Content, mentorship and moderation
6. Notifications, analytics and system configuration

## Required deployment configuration

Set these environment variables in the admin deployment:

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_PUBLISHABLE_KEY`
- `VITE_ADMIN_API_URL`

Set this Edge Function secret/environment value:

- `ADMIN_APP_ORIGIN` — the exact final admin origin, such as `https://admin.mela.app`

Do not use a broad shared origin for `ADMIN_APP_ORIGIN`. The `SUPABASE_SERVICE_ROLE_KEY` remains server-side only.

## Important bootstrap step

The first authorized administrator must be inserted into `admin.admin_users` by a trusted server-side migration/operation. There is intentionally no browser-side self-promotion path.

## Security rule

No admin UI action is trusted merely because it came from this application. Every privileged operation must be authorized server-side and recorded in the audit trail. Do not treat a client-side route guard, a `profiles.role` value, or a shared hosting path as an authorization boundary.
