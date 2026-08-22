# MELA Central Admin Dashboard

Standalone administrative control plane for the MELA platform.

## Implemented foundation

- Separate Vite/React application in its own repository
- Separate Netlify project: `mela-central-dashboard`
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
- Netlify SPA routing configuration

## Security architecture

The browser never receives a Supabase service-role key. The browser uses only the publishable key and a normal authenticated user session. Privileged operations go through the `mela-admin-api` Edge Function, which verifies the caller, checks the private admin role/permission tables, requires MFA, and writes audit records for privileged administrative actions.

## Build order

1. Authorization and access control foundation — implemented
2. Audit logging — schema and API foundation implemented
3. Operational dashboard — next
4. User/employer/payment/dispute operations
5. Content, mentorship and moderation
6. Notifications, analytics and system configuration

## Required deployment configuration

Set these environment variables in the admin deployment:

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_PUBLISHABLE_KEY`
- `VITE_ADMIN_API_URL`

Set this Edge Function secret/environment value:

- `ADMIN_APP_ORIGIN` — the final admin origin, such as `https://admin.mela.app`

The `SUPABASE_SERVICE_ROLE_KEY` remains server-side only.

## Important bootstrap step

The first authorized administrator must be inserted into `admin.admin_users` by a trusted server-side migration/operation. There is intentionally no browser-side self-promotion path.

## Security rule

No admin UI action is trusted merely because it came from this application. Every privileged operation must be authorized server-side and recorded in the audit trail.
