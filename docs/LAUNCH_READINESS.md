# MELA launch readiness — 2 October 2026

Both frontends are deployed to GitHub Pages. The database repairs below are applied. Public login/signup screens and deployment checks pass; authenticated browser, email-delivery, and financial readiness remain unverified.

## Applied backend repairs

- Corrected `private.is_admin_user()` so SECURITY DEFINER ownership does not grant administrator access to ordinary callers. Preserved trusted database maintenance, Auth-service profile synchronization, and service-role access.
- Removed equivalent owner-role shortcuts from profile security triggers.
- Repaired signup and profile-completion language values to match the actual profile constraint.
- Allowed the trusted signup trigger to create referral codes without an end-user session. Removed anonymous and authenticated execution of the automatic commission-processing function.
- Deployed `mela-admin-api` version 22 with JWT enforcement. It checks MFA against the validated bearer token, restricts operational queues by module permission, bounds pagination, validates request shapes, prevents caching, and applies privileged changes together with their audit records in one database transaction.
- Imported existing deployed API corrections into the repository, including moderation statuses, feature-flag counts, commission summaries, and access-request role names.

The seventeen new migration filenames match the versions recorded in the live database. Do not apply them again to that project.

- Added a service-only, action/column-whitelisted audited update RPC, permission checks, target-row locks, and stale-record conflict rejection. Corrected user/employer/report status lists against live constraints and rejected string booleans.
- Live transactional regression confirms update plus audit, stale-write rejection, unsupported-column rejection, non-admin rejection, and denied browser execution. Test records were rolled back. API regression simulates database RPC failures; an actual audit-insert outage was not induced.

- Repaired legacy review-trigger statuses and employer posting policies, hardened registration review-field protection, and implemented separate audited company verification. Approved pending vacancies move to open; visibility still requires source verification and a valid deadline. Suspension removes learner visibility using current verification state.
- Added a rollback-only database journey covering registration → review → approval → verification → posting → moderation approval → learner application → verification suspension. No production test records were retained.

## Published frontend changes

- Consumer app: repaired the broken email-verification source, implemented password recovery, added retryable profile errors and account-status handling, corrected parent-link creation/redemption, improved network-error handling, split feature screens into lazy-loaded bundles, and repaired opportunity submission to include all required database fields.
- Admin app: permission-filtered navigation, backend error messages, configuration failure screen, and live operational modules with permission-filtered registration approvals, separate company-verification decisions, opportunity moderation, and report resolution. Payment/payout and feature-flag tables remain read-only.
- Both repositories run regression tests before CI builds.

## Verification evidence

- Consumer app: 22 regression tests; production build passes.
- Admin app/API: 38 regression tests; production build passes.
- Live database: transactional tests pass for creation and confirmation triggers for student, parent, teacher, and company accounts; parent/teacher/company profile completion; practice start/submit/complete; parent invitation redemption; and rejection of self-promotion. All test records were rolled back. These tests do not replace an HTTP signup and email-delivery test.
- Live admin endpoint: requests without authentication return HTTP 401.
- 263 public/admin tables inspected; all have RLS enabled.
- Production dependency audit: no reported vulnerabilities in the consumer app's installed production dependencies.

## Remaining release gates

1. Frontend publication completed on GitHub Pages: https://melakulms.github.io/mela-app/ and https://melakulms.github.io/Mela-central-dashboard-/. Both deployment jobs and main CI checks succeeded.
2. Verify signup email delivery, configured redirect allowlists, password reset, and administrator MFA in an authenticated browser. The cloud browser loads the published public screens. A secure administrator sign-in attempt returned Failed to fetch; backend Auth settings and preflight checks returned HTTP 200, so authenticated access is not verified. No credentials were inspected or retained in this report.
4. Implement and test the dedicated dispute and provider payout workflows. Registration, verification, opportunity-review, and report-resolution controls are implemented; frontend browser verification remains outstanding.
5. Complete payment-provider sandbox verification and authenticated two-player Arena browser verification. Employer registration, separate verification, posting, approval, application and suspension visibility passed rollback-only database tests; browser verification remains outstanding.
6. Review the remaining callable SECURITY DEFINER functions individually. The Supabase advisor reports 109 notices; many are intentional wrappers, so blanket revocation would break features. Leaked-password protection is also reported as disabled and needs configuration.

The no-policy notices for private admin/service-only tables are not evidence that those tables should be granted browser access.

## GitHub Pages release and finance safety

The owner selected GitHub Pages on 2 October 2026. Email confirmation and recovery redirects preserve `/mela-app/`; admin API CORS explicitly permits `https://melakulms.github.io` and rejects unknown origins. Both GitHub Pages deployment workflows succeeded after aligning the deployment runtime with Node 22.

`mela-finance` version 5 validates users through Auth, separates payout verification from initiation, claims pending requests in the database before provider submission, avoids resubmitting queued/failed requests, and refuses to finalize transfers from a mere API success envelope or mismatched reference/amount/currency. Escrow verification now uses the same atomic finalizer as the callback. Nine mocked finance tests pass; service-only claim privileges and the disabled payout gate were checked live. Successful claims under enabled payouts, real provider transactions, and settlement remain unverified.

Payments, payouts and paid work remain disabled in the live feature flags. Disputes use the existing contract/escrow hold RPC and reports table. A user filing screen and MFA/permission-protected support inbox are now implemented. Provider reconciliation, payout/refund settlement, and a complete resolution workflow remain unfinished. Do not enable the financial features before sandbox and dispute-readiness work passes.

## Publication evidence

Merged consumer PR #5 and admin PR #1. Runtime correction commits: consumer `9b5e5efe8552be2c72974f9c337e8aeee2f44805`; admin `cbf5d68ec0932b5202c81cf213b51f8246a3d94f`. Pages workflow runs `36973141852` (consumer) and `36973171010` (admin) succeeded. Public browser checks confirm consumer login, signup role choices, empty-email reset validation, and admin sign-in rendering. Backend preflight allows the GitHub Pages origin. These checks are not authenticated end-to-end verification.

## Learning-flow repairs and verification

- Arena now provides participant readiness and creator-only start controls, polls matchmaking and live state, surfaces retryable load errors, restores already-submitted answers, submits choice IDs in the JSON-string format expected by the answer keys, and displays actual server scores rather than assuming an `is_correct` response field.
- Applied `repair_arena_start_and_question_choices` (`20261002081043`): require an authenticated creator/admin, require all joined players to be ready, and copy assessment choices into the eight generated quiz rounds. No answer keys are copied into round configuration.
- Rollback-only two-player database regression passes for queue matching, readiness enforcement, creator authorization, eight-round generation, choice availability, correct/incorrect scoring, duplicate-submission rejection and outsider rejection. Full timed progression, rating settlement, and two authenticated browsers remain unverified.
- Study Materials now opens content through the existing entitlement-checking material RPC and respects a locked response even if library access has changed. Content is rendered as text, without executing embedded HTML. Live RPC verification confirms free access and paid-content locking without an entitlement.
- Practice now accepts written answers for questions without choices, blocks additional submissions while saving, and shows pending grading without labeling it incorrect.
- Current local regression totals: 22 consumer tests plus 38 admin/API/finance tests, all passing. Both production builds pass. Security-advisor counts remain 109 authenticated SECURITY DEFINER notices, nine no-policy informational notices, and the existing leaked-password-protection warning.

- A four-player batch regression initially reproduced duplicate matchmaking: a cursor row already paired as another player was reused. The matcher now skips queue rows already marked matched. The same rollback-only regression passes with exactly two matches and one match per player.

## Next-phase security and dispute repair

- Reproduced and repaired premature Arena finalization: non-admin creators must reach the final round before ending a match.
- Repaired two marketplace/membership caller-role triggers by making them SECURITY INVOKER. Direct-client assignment and completion forgery are denied; ordinary posting/editing and authorized task awarding still pass rollback-only tests.
- Added user contract dispute controls in Earn & Work and Employer Portal, plus a support-only administrator dispute inbox. Filing freezes the contract/undisbursed escrow and creates one report; retries do not create duplicates. This does not initiate refunds or settle transfers already in flight.
- The original no-dispute workflow statement is superseded: an existing hold/report RPC was discovered and connected. There is still no dedicated settlement/resolution workflow.
- Current verification: 53 automated tests (22 consumer, 38 admin/API/finance), both builds, transactional Arena/marketplace/dispute tests. See SECURITY_REVIEW.md for the 109-function inventory and the limits of this targeted review.
- Remaining concrete configuration gates: authenticated admin/email verification, unavailable Auth configuration access for leaked-password protection, and real Chapa sandbox evidence. Financial flags remain disabled.

## Moderation follow-up

- General moderation cannot close contract disputes. Both API and frontend reject that path so an unresolved escrow hold cannot be presented as settled.
- Reports under review remain visible in both queues. Moderation query failures now return an error instead of a misleading empty result.
- Closed reports cannot be reopened through the general review action, and closure requires a bounded written reason.
- Seven new regression cases pass; current admin/API/finance total is 38. The existing 22 consumer tests were not rerun because this release changes only the admin application.

## Section-by-section frontend follow-up

The consumer repository's `docs/SECTION_REVIEW.md` records all main sections/subsections and remaining limits. This release adds a lesson reader with saved completion, assessment recovery, challenge/proposal error handling, teacher classrooms, learner classroom joining, mentor decision recovery, official external application links, and connection/language error feedback. Consumer tests now total 27; admin tests remain 38. Both builds pass.

Applied `20261002175728_protect_classroom_detail_access`: authorize the complete classroom response before returning learner details. Live rollback tests cover teacher creation, learner joining, authorized details and outsider denial. No test users or classrooms remain. The security review remains targeted, not exhaustive.

Course-level certification/progress aggregation, parent learner detail, educator observations, challenge team workflows, mentorship scheduling, financial settlement, and authenticated end-to-end verification still require work. Do not describe all sections as production-ready.
