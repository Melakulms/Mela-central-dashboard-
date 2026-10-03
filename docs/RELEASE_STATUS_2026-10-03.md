# Release status — 3 October 2026

## Confirmed changes and verification

- Consumer PR #19 merged as `ecbf2750080fbaebae895f29b3b28e2f895094b2`. Both main checks and Pages deployment run `37094375199` succeeded. The fix prevents failed teacher refreshes showing stale rosters or classroom-creation controls.
- Consumer: 45 automated tests and production build pass.
- Admin MFA access resolution now treats assurance/factor errors as failures with retry, not as missing MFA enrollment. Backend MFA confirmation remains required. Stale async access results are discarded after session changes. Signout errors are visible, successful signout clears password/code fields, and authenticator input is labeled.
- Admin: 49 automated tests and production build pass. Five new access-resolution regressions cover lookup failures, verified-factor selection, enrollment eligibility and backend MFA confirmation.
- Local Chromium fixture verifies failed MFA lookup → retry → existing authenticator challenge → signout, without accidental enrollment, page JavaScript errors or mobile overflow. This uses intercepted requests and is not successful production MFA verification.
- Both live public login screens reached Supabase and returned `Invalid login credentials` for a nonexistent test account. No real credentials or accounts were used. Both screens had no page JavaScript errors or 360px horizontal overflow. The test browser used a proxy-certificate exception; these checks do not certify TLS trust on real user devices.
- Published learner app, Auth health and public language Data API smoke checks succeeded.

## Current external or incomplete release gates

These are not satisfied by passing tests or merging code:

- Successful real-account login, admin MFA, signup email delivery and recovery redirect verification.
- SMTP/service configuration and leaked-password protection. The connected tools do not expose Auth configuration updates; the live advisor still reports leaked-password protection disabled.
- Payment-provider sandbox evidence and complete dispute settlement/reconciliation. Financial features must remain disabled until verified.
- Remaining privileged-function authorization review. Current advisor inventory: 113 authenticated SECURITY DEFINER functions; one intentionally public certificate-verification function; nine no-policy private/service tables. Counts alone do not establish vulnerabilities or justify blanket grants/revocations.
- Educational/editorial and translation certification, child-safeguarding journeys, human accessibility review, backup restoration, load/capacity testing, and any required legal approvals remain pending in the live readiness register. Do not mark these complete without evidence.

The live readiness register also includes supply and provider requirements. Its statuses were inspected read-only; no readiness flags, approvals or financial settings were changed.

Password-protection remediation: https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection
Privileged-function review: https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable

## Section recovery follow-up

- Mela Next now offers the exact goal types supported by the learner's education stage. Unknown stages cannot submit a goal; server eligibility rules remain authoritative.
- Career-coach requests now release their busy state after thrown network errors, preserve the question for a manual retry, reject empty replies, and avoid duplicate submissions.
- Educator review distinguishes unavailable access checks from denied access, supports retry, clears old queue results on reload, and blocks changing review modes during requests.
- Teacher verification clears stale rows and the selected decision form on filter changes or refresh, and guards duplicate decision submission.
- Local verification: consumer 54 automated tests and production build passed; admin 49 automated tests and production build passed. These checks include mocked network failure recovery, not real-account acceptance testing.
- No database permissions, content approvals, payment flags, or launch-readiness declarations were changed by this follow-up. The incomplete release gates above still apply.
