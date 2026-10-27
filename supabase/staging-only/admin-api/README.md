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
- Supabase reports ACTIVE and verify_jwt=true.
- Fresh cloud browser visit to https://mela-admin-staging.vercel.app/Mela-central-dashboard-/ renders Administrator sign in.
- No application console errors were observed (one unrelated browser-extension metadata error).

## Blockers
The staging service_role has no USAGE on admin schema and no SELECT on admin.admin_users or admin.roles. The deployed API intentionally fails closed with ADMIN_REGISTRY_UNAVAILABLE until a separately reviewed private-registry integration is implemented. Deployment is not a claim that authenticated admin operations work.
There is no owner Auth account and no administrator. No owner enrollment, email, password or MFA secret was created.
Real MFA sign-in and privileged operations remain untested.

Vercel project/deployment summaries are readable, but environment listing returned 404 and deployment listing/protected-fetch returned 403 with the current connection. The Vercel CLI is not installed. Public site observation worked without bypass or changing deployment protection.
The current staging alias points to commit 608edeb1ba7976f8ecfe22968de24757ec794b46.
These sources are outside automatic migrations and production function paths.
