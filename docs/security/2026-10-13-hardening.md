# MELA security hardening — 13 October 2026

This is a targeted source and live-backend security review, not a certification that every feature is secure. Production project: `duizgtmbptmlbyipreqg`.

## Applied protections

- Replaced 35 database policy checks based on a legacy profile role with the central super-admin registry, active-account and MFA boundary. Existing owner/participant predicates remain intact.
- Required MFA unconditionally in the main administrative API and denied suspended, banned, deleted or missing administrator profiles before privileged reads/writes.
- Retired the old administrator API and old source-recheck worker. Both now return HTTP 410 and perform no database or outbound network operations. The current Central Admin API remains available. Automated checks through the retired source worker are paused.
- Made beta recovery codes single-use under concurrent requests using an atomic conditional update before the password change. Account throttling no longer depends on IP headers. Bounded password and recovery-code length; recovery claims are restored on an explicit password-provider failure.
- Removed client write privileges for assessment result scores; retained owner reads and trusted grading paths.
- Removed browser execution privileges from seven internal maintenance/trigger functions. Trusted triggers and service jobs retain their intended access.
- Added deletion-state checking to the common account-access predicate.
- Removed development loopback connections from both production content security policies.
- Updated `source-map-js` from 1.2.1 to 1.2.2 in both lockfiles and made admin CI use reproducible `npm ci` installs.

## Verification

- Learner app: 213 tests passed; production build passed.
- Admin app: 318 tests passed; production build passed.
- Both complete npm dependency audits reported zero known vulnerabilities after the update. This does not prove the absence of unknown vulnerabilities.
- Live rollback-only SQL regression passed: profile-only admin denied, AAL1 admin denied, active registry super-admin with AAL2 accepted, suspended account denied, forged score insertion denied, own-profile read preserved. Temporary accounts and rows were rolled back.
- Existing live rollback regressions passed for private-table isolation, assessment grading integrity, and course completion/certificate issuance after the grant changes.
- Live catalogue confirms 35 updated policies, zero remaining `p.role = 'admin'` policy predicates, zero public tables without RLS, and no authenticated INSERT grant on assessment results.
- Deployed function read-back matched the reviewed source: `mela-admin` v5, `mela-source-recheck-v30` v3, `mela-admin-api` v25, `mela-beta-auth` v4.
- Live HTTP checks: unauthenticated current admin API 401; both retired endpoints 410; beta-auth status 200. No real user password was changed to test recovery.
- All 265 public tables have RLS; all seven storage buckets are private with size/type limits; all three public views use security-invoker mode. These settings do not replace per-policy authorization review.
- Pattern scanning current app/backend source found no embedded provider secret, Supabase secret key or service-role JWT. Repository history and all deployed function versions were not exhaustively scanned.

## Remaining release work

1. Move the administrator application to a separate origin. Separate URL paths on `melakulms.github.io` are not an origin security boundary. In-memory admin sessions reduce persistent-token exposure but do not establish origin isolation. Add server-delivered frame-ancestor, HSTS and related security headers on hosting that supports them; a meta CSP cannot enforce frame-ancestors.
2. Enable Supabase leaked-password protection. The live advisor reports it disabled; this setting was not changed. Review CAPTCHA, Auth rate limits, recovery/session expiry and legitimate signup usability together. See [Supabase password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).
3. Finish manual authorization review of the remaining RPCs and older deployed services, including hosted competitions, older AI entry points, content approval/version checks, and deletion/session revocation. The live advisor still flags 96 authenticated and three anonymous security-definer RPCs for review; these warnings alone do not prove exploitable access. Twenty-three no-policy RLS notices principally describe intentionally closed service/private tables; do not add permissive policies merely to remove them.
4. Run end-to-end tests with dedicated student, teacher, employer and administrator accounts, including actual MFA, session revocation and account recovery. No owner credentials or existing users were used in this audit.
5. Rehearse backup restoration, incident response, upload malware handling and production abuse limits. Complete safeguarding/privacy review for children before public launch. Payments remain deferred.

The recovery flow fails closed if its worker stops between consuming a code and completing the Auth update; administrator-assisted recovery may be required in that rare case. A durable recovery workflow would improve availability. Retired endpoints must not be restored to their previous insecure versions during rollback.

## Deployment record

Database migration: `20261013183309_security_boundary_review` (the server-assigned migration version is preserved in this repository). Backend changes are live. Frontend source publication and GitHub Pages deployment are tracked by their repository commits and workflow runs.
