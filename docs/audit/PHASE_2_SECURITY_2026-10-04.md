# Phase 2 security work and evidence

Status: **in progress; not certified**. Changes below are live and stored as migrations. No provider credentials, content approvals, financial flags, or launch-register completion flags were changed.

## Applied changes

- `20261003222024_harden_private_tables_and_review_indexes.sql`: RLS on twelve previously unprotected private tables, explicit backend-service policies, browser grant revocation, and four covering foreign-key indexes. All 259 public, seven admin and sixteen private tables now have RLS. Direct browser access to private data remains denied.
- `20261003222127_repair_coin_ledger_and_badge_invariants.sql`: schema-qualified coin trigger, atomic checked balance update, nonzero/non-null entries, nonnegative profile balances, append-only ledger including truncate protection, and service-only `record_coin_event` with payload-bound replay protection using a stable event UUID.
- Badge counter refresh now handles reassignment as well as insert/delete, locks profiles before recounting, and corrects existing drift. Post-change drift count is zero.

The coin API accepts the same business-event UUID on retries. Callers must reuse that ID; generating a new random ID on every retry defeats business-event idempotency. Existing deployed reward-handler integration and concurrent multi-connection testing remain to audit. This API creates no paid referral eligibility and initiates no payment.

Append-only history deliberately rejects deletion, including an attempted cascading account deletion that would erase ledger entries. Account erasure must use a legally reviewed retention/anonymization workflow before coin rewards are enabled. There are currently zero ledger rows and zero nonzero coin balances; test data was rolled back.

## Tests run against live schema with rolled-back fixtures

| Regression | Result | Scope |
|---|---|---|
| coin_and_badge_invariants.sql | Pass | Credit, valid debit, repeated event, mismatched replay rejection, overdraft rollback, append-only UPDATE/DELETE, mint denial, cross-user ledger denial, badge insert/move/delete |
| private_table_boundaries.sql | Pass | RLS and direct browser denial for all private tables; anonymous/read and browser/write grants absent |
| user_journeys.sql | Pass | Four-role database registration/confirmation, profiles, practice, parent link, self-promotion rejection |
| learning_material_access.sql | Pass | Free access and paid-content denial without entitlement |
| course_credentials.sql | Pass | Progress aggregation, credential issuance, immutable completion evidence, certificate verification |
| guardian_progress.sql | Pass | Linked verified guardian allowed; outsider denied |
| mentorship_lifecycle.sql | Pass | Request acceptance, scheduling, reading, cancellation authorization |
| assessment_integrity.sql | Pass after fixture correction | Server grading, credential and outsider checks; expiry finalization |
| assessment_expiry_finalization.sql | Pass after fixture correction | Incomplete timed-out attempt safely becomes void |

Assessment fixture correction: the old tests impersonated an admin by profile role to move fixture timestamps. The stricter registry authority correctly rejected that. Tests now set the timestamp as the database maintenance actor, then return to the learner role to exercise the real submission boundary. No production authorization was relaxed.

Nine SQL regression files passed. This does not equal nine complete product certifications. No 5,000-user test or multi-connection ledger stress run was performed against production.

## Advisors and dependency scan

Before: four missing foreign-key indexes. After: zero; remaining performance notices are 245 unused-index INFO findings (including the four newly created indexes). Do not drop them without workload evidence.

Security remains: 112 authenticated SECURITY DEFINER notices, one intended anonymous certificate-verification notice, eleven no-policy INFO notices, and disabled leaked-password-protection WARN. No ERROR-level advisor finding appeared. Private/admin tables without browser policies are intentional default-deny boundaries, not a request to grant browser access.

Production npm dependency audits returned zero reported vulnerabilities in both current checkouts. A targeted tracked-file scan found no known-format secret keys or private-key blocks. This is not an exhaustive Git history, entropy-based, or deployed-secret audit; no credential rotation was performed without an identified secret.

References:
- https://supabase.com/docs/guides/database/postgres/row-level-security
- https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable
- https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection

## Remaining Phase 2 gates

1. Recover/reconcile the historical schema and omitted Edge Function sources, then prove a fresh staging restore. A migration list alone cannot reconstruct the database.
2. Finish individual negative authorization review of the 112 authenticated privileged RPCs, associated helpers and remaining per-role policies. Do not replace the review with blanket grants/revocations.
3. Complete financial/provider/referral/escrow invariants and full admin/moderation audit coverage. The existing Chapa-only model does not meet the requested provider requirements.
4. Verify backend reward callers use stable event IDs, concurrent ledger behavior, immutable balance provenance, and legal account-erasure integration.
5. Enable supported leaked-password protection and validate Auth/SMTP/session behavior with real accounts.
6. Complete historical/deployed secret scanning, safe rotation if actual exposure is found, backup/restore evidence and operational review.

OWNER_ACTION_REQUIRED: Auth/password-protection and Brevo configuration access; merchant sandbox onboarding and official documentation for both requested providers; legal retention decision; secure access to staging/backup/deployment administration where not exposed by current tools. External approval dates remain uncommitted. Phase 3 must not be certified while these gates remain open.
