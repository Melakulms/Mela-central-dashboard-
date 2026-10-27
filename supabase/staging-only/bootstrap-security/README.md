# Staging bootstrap security repair

Target: `tungqfmypuwzeyrtaseh` only. Production was not changed.
Applied through the connected SQL tool with an explicit staging project ID on 2026-10-27.

This supersedes the proposed five-line seed migration. That migration is not present on main and must not be added to the shared migrations directory. These manual psql files are outside automatic migrations and refuse connections whose psql HOST is not the exact staging direct database hostname. Use trusted TLS settings and credentials from the secure operator environment; never paste credentials into chat.

## Repair
- Preserve the existing function ACL (postgres only); do not reopen public RPC access.
- Empty search path with explicitly qualified schema objects.
- Require an existing non-anonymous Auth user with the designated verified owner email.
- Require an aal2 JWT before assigning the first administrator. MFA enrollment therefore precedes bootstrap.
- Fail closed when the singleton row is missing.
- Keep FOR UPDATE serialization and require exactly one consumption update.
- Refuse reuse when consumed fields, any prior administrator (including inactive), or a completion audit record exist.
- Return and audit handled denials, including missing role and missing lock.
- Seed only if no administrator or completion audit exists; never overwrite an existing row.

## Verification
Nine DB tests passed on staging using temporary synthetic Auth data and simulated JWT claims, followed by ROLLBACK:
unauthenticated, non-owner, unverified email, aal1, missing lock, successful aal2 bootstrap, reuse, repeated seed, and denial auditing.
No persistent test account or administrator was created. The test success assignment existed only inside the rolled-back transaction.

The security advisor still reports unrelated existing payment-view / RPC and password-protection findings; this is not a platform-wide security clearance.

## Remaining enrollment work
No owner Auth account exists in staging. Do not fabricate a verified owner or grant a permanent administrator as a test.
The owner must complete approved Auth enrollment and MFA. Existing restricted execution access is preserved; a separately reviewed owner setup procedure must transport verified session identity to bootstrap.
No real Auth sign-in, Google Authenticator challenge, simultaneous-call test, admin API deployment, or browser startup repair is claimed by this change.
The repository admin API source contains an aal2 check, but its staging deployment was not verified here.
Audit persistence requires the caller transaction to commit.
