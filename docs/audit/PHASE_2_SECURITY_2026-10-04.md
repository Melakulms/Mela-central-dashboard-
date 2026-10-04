# Phase 2 security work and evidence

Status: **in progress; not certified**. Changes below are live and stored as migrations. No provider credentials, content approvals, financial flags, or launch-register completion flags were changed.

## Applied changes

- `20261003222024_harden_private_tables_and_review_indexes.sql`: RLS on twelve previously unprotected private tables, explicit backend-service policies, browser grant revocation, and four covering foreign-key indexes. All public/admin/private tables audited in this phase have RLS. Direct browser access to private data remains denied.
- `20261003222127_repair_coin_ledger_and_badge_invariants.sql`: schema-qualified coin trigger, atomic checked balance update, nonzero/non-null entries, nonnegative profile balances, append-only ledger including truncate protection, and service-only `record_coin_event` with payload-bound replay protection using a stable event UUID.
- Badge counter refresh now handles reassignment as well as insert/delete, locks profiles before recounting, and corrects existing drift. Post-change drift count is zero.
- `20261003082220_restore_verified_educator_question_review_submission.sql` plus the subsequent educator-review migrations restore controlled question-review submission and bind it to approved teacher identity, approved teaching subjects, explicit reviewer authorization and server-side subject checks.
- `20261003082930_enable_qualified_educator_content_review_workflows.sql` provides chapter-review queue/item/claim/submit workflows with private append-only decision history. The public API uses SECURITY INVOKER wrappers; private implementations validate the current caller and subject eligibility.
- `20261003085029_restore_language_review_operations_for_authenticated_reviewers.sql` restores assessment-language review operations through explicit reviewer/admin execution boundaries rather than direct table writes.
- `20261004040739_harden_question_review_read_wrappers.sql`: converted `get_question_review_queue_v18` and `get_question_review_slice_v18` public wrappers from SECURITY DEFINER to SECURITY INVOKER, explicitly granted only authenticated/service-role execution on the necessary private implementations, and kept anonymous execution revoked.
- `20261004041220_harden_question_reviewer_capability_wrapper.sql`: converted `can_review_questions_v18()` to an invoker public wrapper while preserving the private approved-teacher/reviewer-authorization check and explicit authenticated/service-role execution boundary.
- `20261004041516_harden_admin_observability_read_wrappers.sql`: converted `get_platform_launch_readiness()` and `get_platform_operational_health()` to invoker public wrappers backed by their existing private MFA-admin authorization checks.
- `20261004041714_harden_proctor_review_queue_wrapper.sql`: moved the proctor-review queue's privileged assessment/proctor reads into a private SECURITY DEFINER implementation with MFA-admin enforcement and replaced the public function with a SECURITY INVOKER wrapper.
- `20261004042011_harden_read_only_api_wrappers.sql`: converted five more read-only public wrappers to SECURITY INVOKER: `get_data_protection_compliance_pack`, `get_my_question_bank_overview`, `get_question_catalog_v18`, `get_question_quality_progress_v21`, and `get_question_subject_detail_v18`. The existing private caller/admin/reviewer checks remain authoritative.

The coin API accepts the same business-event UUID on retries. Callers must reuse that ID; generating a new random ID on every retry defeats business-event idempotency. Existing deployed reward-handler integration and concurrent multi-connection testing remain to audit. This API creates no paid referral eligibility and initiates no payment.

Append-only history deliberately rejects deletion, including an attempted cascading account deletion that would erase ledger entries. Account erasure must use a legally reviewed retention/anonymization workflow before coin rewards are enabled. There are currently no launch-certified financial ledger balances; test data was rolled back.

## Tests run against live schema with rolled-back fixtures

| Regression | Result | Scope |
|---|---|---|
| coin_and_badge_invariants.sql | Pass | Credit, valid debit, repeated event, mismatched replay rejection, overdraft rollback, append-only UPDATE/DELETE, mint denial, cross-user ledger denial, badge insert/move/delete |
| private_table_boundaries.sql | Pass | RLS and direct browser denial for private tables; anonymous/read and browser/write grants absent |
| user_journeys.sql | Pass | Four-role database registration/confirmation, profiles, practice, parent link, self-promotion rejection |
| learning_material_access.sql | Pass | Free access and paid-content denial without entitlement |
| course_credentials.sql | Pass | Progress aggregation, credential issuance, immutable completion evidence, certificate verification |
| guardian_progress.sql | Pass | Linked verified guardian allowed; outsider denied |
| mentorship_lifecycle.sql | Pass | Request acceptance, scheduling, reading, cancellation authorization |
| assessment_integrity.sql | Pass after fixture correction | Server grading, credential and outsider checks; expiry finalization |
| assessment_expiry_finalization.sql | Pass after fixture correction | Incomplete timed-out attempt safely becomes void |
| question_review_wrapper_security.sql | Pass | Public reviewer reads/capability are invoker wrappers; anonymous execution denied; private review tables remain unreadable; synthetic student has no reviewer capability, receives no review queue and cannot open a slice |
| admin_observability_wrapper_security.sql | Pass | Non-admin/AAL1 access denied; registered AAL2 admin can read launch readiness and operational health through invoker wrappers |
| proctor_review_queue_wrapper_security.sql | Pass | Non-admin access denied; registered AAL2 admin can read proctor-review queue through private implementation/public invoker wrapper |
| read_only_api_wrapper_security.sql | Pass | Learner catalog/detail/own overview still work; learner cannot access educator quality progress or admin compliance pack; registered AAL2 admin can access restricted reads |

Assessment fixture correction: the old tests impersonated an admin by profile role to move fixture timestamps. The stricter registry authority correctly rejected that. Tests now set the timestamp as the database maintenance actor, then return to the learner role to exercise the real submission boundary. No production authorization was relaxed.

The new wrapper regressions were also executed directly against production inside `BEGIN ... ROLLBACK`; no fixture persisted. Separate negative checks with a student identity returned `false` for reviewer capability, an empty review queue, review-slice denial, admin-observability denial, proctor-queue denial, educator-quality denial and compliance-pack denial. Learner-safe question catalog/detail/overview reads succeeded. Positive checks used an existing active admin registry entry with simulated AAL2 claims and succeeded. No approved educator or content approval was fabricated.

These SQL regressions are targeted engineering evidence, not complete product certifications. No 5,000-user test or multi-connection ledger stress run was performed against production.

## Advisors and dependency scan

Before Phase 2 index repair: four missing foreign-key indexes. After: zero; remaining performance notices are unused-index INFO findings. Do not drop them without workload evidence.

Security advisor after this hardening batch: **101 authenticated SECURITY DEFINER notices, down from 112**; one intended anonymous certificate-verification notice; eleven RLS-enabled/no-policy INFO notices; and disabled leaked-password-protection WARN. The eleven removed privileged public endpoints are `get_question_review_queue_v18`, `get_question_review_slice_v18`, `can_review_questions_v18`, `get_platform_launch_readiness`, `get_platform_operational_health`, `get_proctor_review_queue`, `get_data_protection_compliance_pack`, `get_my_question_bank_overview`, `get_question_catalog_v18`, `get_question_quality_progress_v21`, and `get_question_subject_detail_v18`. Each retains authorization in a private implementation where privilege is required. No ERROR-level advisor finding appeared. Private/admin tables without browser policies are intentional default-deny boundaries, not a request to grant browser access.

Production npm dependency audits returned zero reported vulnerabilities in both current checkouts. A targeted tracked-file scan found no known-format secret keys or private-key blocks. This is not an exhaustive Git history, entropy-based, or deployed-secret audit; no credential rotation was performed without an identified secret.

References:
- https://supabase.com/docs/guides/database/postgres/row-level-security
- https://supabase.com/docs/guides/database/functions
- https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable
- https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection

## Remaining Phase 2 gates

1. Recover/reconcile the historical schema and omitted Edge Function sources, then prove a fresh staging restore. A migration list alone cannot reconstruct the database.
2. Continue individual negative authorization review of the remaining 101 authenticated privileged RPCs, associated helpers and remaining per-role policies. Do not replace the review with blanket grants/revocations.
3. Complete financial/provider/referral/escrow invariants and full admin/moderation audit coverage. The existing Chapa-only model does not meet the requested telebirr/CBE Birr provider requirements.
4. Verify backend reward callers use stable event IDs, concurrent ledger behavior, immutable balance provenance, and legal account-erasure integration.
5. Enable supported leaked-password protection and validate public Auth/SMTP/session behavior with real accounts.
6. Complete historical/deployed secret scanning, safe rotation if actual exposure is found, backup/restore evidence and operational review.
7. Recruit/approve real qualified educators and language reviewers, then use the now-functional workflows to create genuine chapter/question/translation review evidence. Engineering availability does not count as human approval.

OWNER_ACTION_REQUIRED: Auth/password-protection and public SMTP/domain configuration; merchant sandbox onboarding and official documentation for both requested providers; legal retention decision; qualified human reviewers; secure access to a disposable staging/backup target where not exposed by current tools. External approval dates remain uncommitted. Phase 3 must not be certified while these gates remain open.

## Video shutdown and historical recovery follow-up

- Reproduced direct video-room creation by an authenticated learner while the live `video_calls` flag was false. The fixture transaction was rolled back.
- Applied `20261004090240_enforce_video_shutdown_boundary` and `20261004090336_refine_video_shutdown_update_checks`. Rooms, participants, signaling and presence now honor the database switch, including privileged RPC writes. Rejoining cannot disclose a room key while disabled. Leaving, ending/removing participation and recording-consent withdrawal remain possible.
- `supabase/tests/video_shutdown_boundary.sql` passes against the live schema with rollback-only fixtures. It covers enabled creation/join and disabled creation, invitation, repeated join, recording request, signaling insert/update, presence insert/update, and leave/end cleanup. Temporary test enablement was transaction-local and rolled back; video/payments/payouts/earn_work remain disabled.
- Recovered SQL for all 607 migration records into `supabase/recovery/history`, separate from active migrations. Every file matches the SHA-256 manifest (`python scripts/verify-recovery-archive.py`). A targeted credential-format scan found no embedded tokens/private keys; the single flagged identity-write was reviewed as a function definition, not account data.
- Fresh restore is NOT verified. The earliest migration alters pre-existing profiles/functions, proving that registry recovery alone is not a complete baseline. A current authorized schema/backup export and isolated staging database remain required. This workspace has no PostgreSQL/Docker runtime or staging connection.
- Latest advisor snapshot: 94 authenticated privileged-function WARN entries, one intentional anonymous certificate verifier, eleven no-policy INFO entries, disabled leaked-password-protection WARN; no missing foreign-key index warning. The count decrease from the prior snapshot includes other intervening hardening and is not attributed to the video fix.
- This closes a video kill-switch bypass, not the complete child-safeguarding/provider/recording certification. Existing peer connections must also be terminated at the video-provider layer when that provider is integrated; database shutdown cannot retroactively disconnect an established external media stream.

OWNER_ACTION_REQUIRED: secure access to an approved baseline backup/schema export and isolated staging database for restore testing; supported leaked-password-protection configuration remains outstanding. Phase 2 remains in progress; no later phase has been certified by this follow-up.
