# Staging admin API deployment

Deployed `mela-admin-api` version 1 only to `tungqfmypuwzeyrtaseh`, with verify_jwt=true.
Source: the admin-hosting-isolation branch's API with explicit staging URL and origin guards.
Only https://mela-admin-staging.vercel.app is an allowed browser origin.
The function refuses another Supabase URL at runtime.
No production deployment or environment configuration was changed.

## Verified
- TypeScript parsed successfully with Node 24 stripTypeScriptTypes.
- Run `node boundary.test.mjs` using Node 24: 11 simulated boundary cases pass.
- Live unauthenticated POST returned 401 UNAUTHORIZED_NO_AUTH_HEADER.
- Live malformed JWT POST returned 401 UNAUTHORIZED_INVALID_JWT_FORMAT.
- Live OPTIONS returned 200 and the exact staging Access-Control-Allow-Origin.
- Supabase reports ACTIVE and verify_jwt=true.
- Fresh cloud browser visit to https://mela-admin-staging.vercel.app/Mela-central-dashboard-/ renders Administrator sign in.
- No application console errors were observed (one unrelated browser-extension metadata error).

## Blockers
The registry integration is now applied through registry-access.psql: REST schemas are public, graphql_public, admin; only service_role gains admin schema USAGE. It has SELECT on six required tables, INSERT on audit_log with sequence USAGE, and EXECUTE on apply_audited_update. No direct admin_users write or bootstrap execution was granted. Anonymous and authenticated roles retain no schema USAGE. A live anonymous REST read returned 401 permission denied for schema admin, confirming exposure does not grant client access. A transaction using SET LOCAL ROLE service_role read all required registry tables successfully. Full authenticated owner operations remain untested.
There is no owner Auth account and no administrator. No owner enrollment, email, password or MFA secret was created.
Real MFA sign-in and privileged operations remain untested.

Vercel project/deployment summaries are readable, but environment listing returned 404 and deployment listing/protected-fetch returned 403 with the current connection. The Vercel CLI is not installed. Public site observation worked without bypass or changing deployment protection.
The current staging alias points to commit 608edeb1ba7976f8ecfe22968de24757ec794b46.
These sources are outside automatic migrations and production function paths.
