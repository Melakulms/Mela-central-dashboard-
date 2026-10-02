# MELA launch readiness — 2 October 2026

Public launch is not yet verified. The database repairs below are applied; the frontend changes still require deployment to the actual hosting projects.

## Applied backend repairs

- Corrected `private.is_admin_user()` so SECURITY DEFINER ownership does not grant administrator access to ordinary callers. Preserved trusted database maintenance, Auth-service profile synchronization, and service-role access.
- Removed equivalent owner-role shortcuts from profile security triggers.
- Repaired signup and profile-completion language values to match the actual profile constraint.
- Allowed the trusted signup trigger to create referral codes without an end-user session. Removed anonymous and authenticated execution of the automatic commission-processing function.
- Deployed `mela-admin-api` version 20 with JWT enforcement. It checks MFA against the validated bearer token, restricts operational queues by module permission, bounds pagination, validates request shapes, prevents caching, and applies privileged changes together with their audit records in one database transaction.
- Imported existing deployed API corrections into the repository, including moderation statuses, feature-flag counts, commission summaries, and access-request role names.

The eleven new migration filenames match the versions recorded in the live database. Do not apply them again to that project.

- Added a service-only, action/column-whitelisted audited update RPC, permission checks, target-row locks, and stale-record conflict rejection. Corrected user/employer/report status lists against live constraints and rejected string booleans.
- Live transactional regression confirms update plus audit, stale-write rejection, unsupported-column rejection, non-admin rejection, and denied browser execution. Test records were rolled back. API regression simulates database RPC failures; an actual audit-insert outage was not induced.

- Repaired legacy review-trigger statuses and employer posting policies, hardened registration review-field protection, and implemented separate audited company verification. Approved pending vacancies move to open; visibility still requires source verification and a valid deadline. Suspension removes learner visibility using current verification state.
- Added a rollback-only database journey covering registration → review → approval → verification → posting → moderation approval → learner application → verification suspension. No production test records were retained.

## Frontend changes awaiting deployment

- Consumer app: repaired the broken email-verification source, implemented password recovery, added retryable profile errors and account-status handling, corrected parent-link creation/redemption, improved network-error handling, split feature screens into lazy-loaded bundles, and repaired opportunity submission to include all required database fields.
- Admin app: permission-filtered navigation, backend error messages, configuration failure screen, and live operational modules with permission-filtered registration approvals, separate company-verification decisions, opportunity moderation, and report resolution. Payment/payout and feature-flag tables remain read-only.
- Both repositories run regression tests before CI builds.

## Verification evidence

- Consumer app: 10 regression tests; production build passes.
- Admin app/API: 110 regression tests; production build passes.
- Live database: transactional tests pass for creation and confirmation triggers for student, parent, teacher, and company accounts; parent/teacher/company profile completion; practice start/submit/complete; parent invitation redemption; and rejection of self-promotion. All test records were rolled back. These tests do not replace an HTTP signup and email-delivery test.
- Live admin endpoint: requests without authentication return HTTP 401.
- 263 public/admin tables inspected; all have RLS enabled.
- Production dependency audit: no reported vulnerabilities in the consumer app's installed production dependencies.

## Remaining release gates

1. Identify the actual frontend hosting projects. The connected Vercel team currently returns no projects. Deploy these branches and verify production environment configuration and SPA routing.
2. Verify signup email delivery, configured redirect allowlists, password reset, and administrator MFA in an authenticated browser. Local browser execution was unavailable and the browser download failed.
4. Implement and test the dedicated dispute and provider payout workflows. Registration, verification, opportunity-review, and report-resolution controls are implemented; frontend browser verification remains outstanding.
5. Complete payment-provider sandbox verification and a two-player Arena test. Employer registration, separate verification, posting, approval, application and suspension visibility passed rollback-only database tests; browser verification remains outstanding.
6. Review the remaining callable SECURITY DEFINER functions individually. The Supabase advisor reports 109 notices; many are intentional wrappers, so blanket revocation would break features. Leaked-password protection is also reported as disabled and needs configuration.

The no-policy notices for private admin/service-only tables are not evidence that those tables should be granted browser access.

## GitHub Pages release and finance safety

The owner selected GitHub Pages on 2 October 2026. Email confirmation and recovery redirects preserve `/mela-app/`; admin API CORS explicitly permits `https://melakulms.github.io` and rejects unknown origins. Frontend publication is being verified through the repository deployment workflows.

`mela-finance` version 5 validates users through Auth, separates payout verification from initiation, claims pending requests in the database before provider submission, avoids resubmitting queued/failed requests, and refuses to finalize transfers from a mere API success envelope or mismatched reference/amount/currency. Escrow verification now uses the same atomic finalizer as the callback. Nine mocked finance tests pass; service-only claim privileges and the disabled payout gate were checked live. Successful claims under enabled payouts, real provider transactions, and settlement remain unverified.

Payments, payouts and paid work remain disabled in the live feature flags. There is no dispute table or user dispute workflow in the current schema; the placeholder is not a completed settlement system. Do not enable the financial features before sandbox and dispute-readiness work passes.
