# Readiness check — 7 October 2026

Decision: unrestricted public launch is still blocked. Payments remain deferred/off.

## Repairs

Both frontends ignore initial session snapshots/errors after a newer authentication event, preventing delayed restoration from undoing sign-out, sign-in or password recovery. Cleanup suppresses callbacks after unmount. Admin changes clear obsolete MFA challenge state and invalidate pending access checks on cleanup. Cancelled learner profile requests no longer update language.

The learner service worker deletes only obsolete MELA shell caches, handles only URLs in its app path, reads its own cache, and does not overwrite the offline shell with HTTP errors or non-HTML responses.

## Verification

- Learner: 84 tests in 23 suites; TypeScript and production build pass.
- Admin: 248 tests in 18 suites; TypeScript and production build pass.
- 22 new regression tests cover session ordering, cleanup, recovery, sign-out and cache isolation.
- Live database checks pass for private-table browser access denial, admin registry/MFA authority, classroom access boundaries and course completion/certificate issuance/evidence immutability. Classroom/course fixtures rolled back.
- Both hosted sign-in screens render in the cloud browser. Authenticated browser journeys were not performed in this checkpoint.
- Live controls: payments, payouts, video calls, challenges and Earn & Work remain OFF. Invite-only beta is enabled. Existing AI gateway limits remain 10 attempts per user and 100 globally per day; legacy routes and provider funding are not certified.

## Remaining launch gates

- Live inventory: 149 active programs, 887 chapters, 142,396 active questions, 23 empty programs, 25 drafts. Source-verified chapters, educator-verified questions, approved chapter reviews and submitted drafts are all zero.
- Qualified curriculum/source-rights review, native-language review and the canonical ordered 53-field list are still required. Drafts are not certified lessons.
- Real-account role journeys, signup/recovery delivery, MFA enrollment/recovery, device and slow-network acceptance remain unverified.
- Supabase advisor: 90 authenticated privileged-function warnings, one anonymous certificate-verifier warning, one leaked-password protection warning, and 15 no-policy informational findings. Warnings require individual assessment; private-table access denial was rechecked successfully.
- AI provider funding, consolidated legacy-route limits, safeguarding evaluation and authenticated provider-backed journeys remain unverified.

These checks do not certify educational accuracy, legal readiness or unrestricted launch. No review evidence was fabricated and no disabled feature was enabled.
