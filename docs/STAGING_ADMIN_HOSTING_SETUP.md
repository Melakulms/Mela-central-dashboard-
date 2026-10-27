# Staging Central Admin hosting — isolated deployment checklist

This document applies **only** to the standalone Vercel project `mela-admin-staging` and Supabase staging project `tungqfmypuwzeyrtaseh`.

Do not merge this staging-specific branch into `main`, which is used by the live Central Admin application.

## Staging project setup

- Source repository: `Melakulms/Mela-central-dashboard-`
- Production branch **within the staging Vercel project only**: `staging/admin-hosting-isolation-20261027`
- Vercel project: `mela-admin-staging`
- Public URL after successful staging deployment: `https://mela-admin-staging.vercel.app/Mela-central-dashboard-/`
- Framework: Vite, output: `dist`
- `VITE_SUPABASE_URL=https://tungqfmypuwzeyrtaseh.supabase.co`
- `VITE_SUPABASE_PUBLISHABLE_KEY`: publishable key from **staging**, never service-role key.
- The browser must not have production Supabase secrets, production service credentials, or extra shared admin credentials.

## Required technical checks before any sign-in

1. Verify the deployed Git commit belongs to this isolated branch and contains both CSP restrictions (`vercel.json`, `index.html`) and the fail-closed staging URL guard.
2. Confirm the Vercel environment variables are bound to the staging backend and no service key was exposed.
3. Check that staging-specific Supabase Edge Functions for administrative auth/authorization are deployed with correct origin restrictions. **As of initial setup, the staging project did not have `mela-admin-api` or `mela-beta-admin`.**
4. Apply only a separately reviewed, explicitly approved, **staging-only** administrator bootstrap migration; it must be audited, one-use, restricted to the authorized owner account, and not based on a spoofable client role.
5. Owner completes personal sign-in and MFA enrollment privately on their Android phone; never post OTPs, setup keys, or passwords in chat.
6. Do not approve mentors, issue invitations, or claim authenticated acceptance until the real AAL2 reviewer and normal registration journeys succeed.
7. Keep payments, live video, group programs and minors disabled throughout the staging validation.

## Status

Staging hosting source configured for review; deployment and signed-in administrator acceptance must be independently verified. This document does not assert a successful deployment or bootstrap.
