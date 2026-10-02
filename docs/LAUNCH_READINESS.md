# MELA launch readiness — 2 October 2026

Public launch is not yet verified. The database repairs below are applied; the frontend changes still require deployment to the actual hosting projects.

## Applied backend repairs

- Corrected `private.is_admin_user()` so SECURITY DEFINER ownership does not grant administrator access to ordinary callers. Preserved trusted database maintenance, Auth-service profile synchronization, and service-role access.
- Removed equivalent owner-role shortcuts from profile security triggers.
- Repaired signup and profile-completion language values to match the actual profile constraint.
- Allowed the trusted signup trigger to create referral codes without an end-user session. Removed anonymous and authenticated execution of the automatic commission-processing function.
- Deployed `mela-admin-api` version 17 with JWT enforcement. It checks MFA against the validated bearer token, restricts operational queues by module permission, bounds pagination, validates request shapes, prevents caching, and reports failed audit writes explicitly.
- Imported existing deployed API corrections into the repository, including moderation statuses, feature-flag counts, commission summaries, and access-request role names.

The four new migration filenames match the versions recorded in the live database. Do not apply them again to that project.

## Frontend changes awaiting deployment

- Consumer app: repaired the broken email-verification source, implemented password recovery, added retryable profile errors and account-status handling, corrected parent-link creation/redemption, improved network-error handling, and split feature screens into lazy-loaded bundles.
- Admin app: permission-filtered navigation, backend error messages, configuration failure screen, and live read-only operational modules for employer/opportunity records, payments/payouts, moderation, and feature flags.
- Both repositories run regression tests before CI builds.

## Verification evidence

- Consumer app: 7 regression tests; production build passes.
- Admin app/API: 11 regression tests; production build passes.
- Live database: transactional tests pass for creation and confirmation triggers for student, parent, teacher, and company accounts; parent/teacher/company profile completion; practice start/submit/complete; parent invitation redemption; and rejection of self-promotion. All test records were rolled back. These tests do not replace an HTTP signup and email-delivery test.
- Live admin endpoint: requests without authentication return HTTP 401.
- 263 public/admin tables inspected; all have RLS enabled.
- Production dependency audit: no reported vulnerabilities in the consumer app's installed production dependencies.

## Remaining release gates

1. Identify the actual frontend hosting projects. The connected Vercel team currently returns no projects. Deploy these branches and verify production environment configuration and SPA routing.
2. Verify signup email delivery, configured redirect allowlists, password reset, and administrator MFA in an authenticated browser. Local browser execution was unavailable and the browser download failed.
3. Move privileged mutations and their audit inserts into a single database transaction. Current API mutations and audit logging are separate operations; failures now return an explicit error, but the state change can still persist without an audit record.
4. Implement and test the dedicated dispute workflow and administrative decision controls. The new operational screens are read-only; they do not constitute complete approval, payout, or dispute workflows.
5. Complete real employer approval/posting/application tests, payment-provider sandbox verification, and a two-player Arena test.
6. Review the remaining callable SECURITY DEFINER functions individually. The Supabase advisor reports 109 notices; many are intentional wrappers, so blanket revocation would break features. Leaked-password protection is also reported as disabled and needs configuration.

The no-policy notices for private admin/service-only tables are not evidence that those tables should be granted browser access.
