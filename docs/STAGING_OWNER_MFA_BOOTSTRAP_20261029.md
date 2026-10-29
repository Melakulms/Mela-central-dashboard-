# Staging first-owner bootstrap — controlled account enrollment

Environment: **Supabase staging** `tungqfmypuwzeyrtaseh`; admin frontend: **separate Vercel staging project** `mela-admin-staging`. Never use the production Supabase project.

## Verified readiness on 29 October 2026
- The one-time `admin.bootstrap_first_super_admin()` lock is present and unused.
- Three existing Auth users have confirmed emails; none is the designated owner.
- Zero administrator registry entries, zero enrolled TOTP factors and zero mentors.
- General registrations stay disabled. Staging-only migration `confirmed_owner_auth_admin_only_staging_20261029` now permits only the designated owner Auth user created **already confirmed by a trusted Auth Admin operation**, while the one-use bootstrap lock is unused. It rejects normal public email-password signup and every other email.
- Staging-only RPC `public.claim_staging_first_super_admin()` was installed with anonymous EXECUTE revoked. It checks staging token issuer and AAL2 before calling the existing owner-email, confirmed-email, one-use, audited bootstrap.
- The admin UI branch offers a single explicit claim button only after the designated owner signs in, verifies TOTP and receives `ADMIN_MEMBERSHIP_REQUIRED` from the real admin API. It does not automatically claim an administrator role.

## One user-controlled prerequisite (cannot be performed through an unauthenticated SQL client)
Using the staging Supabase Dashboard on your own phone: go to **Authentication → Users → Add user → Create new user** for the designated bootstrap email. Choose your own strong password privately and **enable Auto Confirm User** (the new staging registration exception requires an already-confirmed Auth Admin-created owner identity). Confirm the target project is `tungqfmypuwzeyrtaseh` before pressing Create. The trusted dashboard action is required; the assistant cannot impersonate a signed-in Supabase Auth Admin or retrieve the password. Do not paste passwords, MFA setup keys, TOTP codes, private invite links, service-role keys or session JWTs into chat.

**Important:** Public signup and unconfirmed email invitations remain blocked. If the Dashboard displays a registration/confirmation or database trigger error, stop and report only the non-sensitive error code; do **not** enable general registration, create a duplicate owner account, or manually insert into `auth.users`.

After a confirmed account exists:
1. On Android, open the dedicated staging administrator URL and enter the owner email and private password.
2. Complete the existing MELA Central Admin Google Authenticator enrollment on the phone. Verify its current code and reach AAL2. Keep QR/secret private.
3. On the **Administrator access check** screen, choose **Complete first administrator setup**. It calls `public.claim_staging_first_super_admin()` once with the signed-in JWT.
4. Confirm the signed-in `mela-admin-api` reports the `super_admin` role at AAL2.
5. Run read-only structural verifications: `admin.admin_users` contains exactly one active super-admin and the lock was consumed by that same user; the admin audit has exactly one bootstrap success entry. Run a separate sign-in and MFA step-up check.
6. Only then create separately authorized reviewer and mentor accounts and review real evidence before mentor verification. No fake qualifications, self-review, or bypassed AAL2.
7. Test guardian links using verified and authorized adults and age-appropriate learners. Keep Grade 1–10 direct booking blocked. Test successful scheduling, cancellation, follow-up notes, completion, and recovered-factor workflows with genuinely signed-in test users.
8. Keep payments and live video OFF; do not promote the 16-section mentorship foundation to production until role, privacy, and real AAL2 E2E tests pass.

## Safety checks
- `anon` EXECUTE = false; `authenticated` EXECUTE = true; SQL caller without staging JWT returns `staging_session_required`.
- The backend must reject non-owner, unconfirmed owner, and AAL1 sessions. UI tests mock these cases, but **mocked sessions are never equivalent to a real signed-in MFA test**.
- Production migration remains unchanged; the separate staging code is NOT automatically deployed to main.
