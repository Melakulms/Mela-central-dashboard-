# MELA privacy rights — data footprint and fulfillment gates

**Production schema snapshot:** 4 November 2026. **Status:** read-only discovery for legal, safeguarding, privacy, and engineering review. **Not approved for real-user export, deletion, or case closure.**

## Verified coverage (metadata only)

The production PostgreSQL catalog has **308 application base tables** across `public` (276), `private` (23), and `admin` (9). Of those, **212 distinct tables** have a direct foreign key to either `public.profiles` (**161 tables**) or `auth.users` (**51 tables**). These sets did not overlap in this snapshot. The inventory is not a personal-data record count and does **not** imply that the other 96 tables contain no personal information.

Production Supabase Storage has **8 buckets**, each currently marked `public=false`: `avatars`, `call-recordings`, `career-documents`, `employer-documents`, `practice-submissions`, `task-attachments`, `teacher-credentials`, and `work-submissions`. A private bucket flag is not proof of secure subject-level authorization; Storage RLS, ownership paths, object sharing, backups, signed URLs, and third-party copies require separate review. Authentication (`auth.users`, sessions and identities), Storage object metadata, backups, logs and outside vendors are **additional** to the 308 application tables.

These numbers were read from schema metadata; **no user rows, document content, storage objects, secrets or personal details were fetched**. Re-run the accompanying read-only SQL before relying on the snapshot.

## Scope for each right-to-access, export, rectify or erase case

The following categories are **starting points**, not an exhaustive list of personal-data sources:

| Domain | Examples of related production tables or data | Required review |
| --- | --- | --- |
| Identity and role profiles | `profiles`, `student_profiles`, `teacher_profiles`, `mentor_profiles`, `parent_profiles`, `educator_profiles`, `profile_documents`; Auth identities | Exact individual/role relationship, necessary identifying details, professional verification evidence, scope and redaction |
| Minors, guardians and safeguarding | `guardian_relationships`, `parent_link_invites`, `learner_support_signals`, `reports`, `data_protection_incidents` | Independently verified guardian authority, child protection, linked and third-party rights, preservation obligations |
| Learning, assessments and progress | `practice_attempts`, `assessment_attempts`, `lesson_progress`, `course_enrollments`, `career_passport_entries` | Learner ownership, grading evidence, school/teacher data, required learning records, redaction |
| AI and communication records | `ai_tutor_usage`, `mela_ai_sessions`, `mela_ai_messages`, `mela_ai_memory`, `notifications` | Personal content in text/JSON, retention, provider copies, safety and other users' messages |
| Mentorship and professional interaction | `mentorship_sessions`, `mentorship_requests`, `mentor_availability`, `applications`, `application_notes` | Both participants' information, safeguarding/consent, independent notes, employment records |
| Payments, referrals and ledger | `payments`, `coin_transactions`, `earnings_ledger`, `mela_paid_memberships` | Tax/accounting/anti-fraud retention, bank-provider reconciliation, payout disputes and references |
| Trust, admin and privacy records | `admin.audit_log`, `data_subject_requests`, `privacy_review_checkpoints`, `proctor_audit_logs` | Evidence preservation, minimum-necessary access, legal retention, record-of-review and audit integrity |
| Private Storage | All eight buckets listed above | Authenticated ownership resolution, nested paths, signed URLs, originals/copies, redaction and deletion/backup plan |

**Reference discovery is not sufficient:** many records link through another entity (e.g., mentor profile or organization), through JSON/text identifiers, via polymorphic keys, to another account, or through a storage object path. `public.mentor_availability` is one example with a `mentor_id` but no *direct* FK to `profiles`/`auth.users` in the first-pass heuristic. Do not mistake an indirect relationship for missing privacy coverage.

## Verified foreign-key deletion hazard

Production metadata shows `public.data_subject_requests`, `public.payments`, `public.profile_documents` and `public.guardian_relationships` have at least one `ON DELETE CASCADE` reference to `public.profiles`. Some of those tables have **multiple FK constraints with different delete actions**. `admin.audit_log.actor_user_id` references `auth.users` using `ON DELETE SET NULL`.

This means **deleting `profiles` or `auth.users` directly is not an acceptable privacy-rights fulfillment mechanism**. It could remove rights request records, payment/safeguarding evidence, documents or other connected data automatically, without an approved retention assessment. Deleting an Auth user also has session/token implications. A case cannot be closed simply because the target profile row disappeared.

## Mandatory, independent fulfillment gates — all remain UNVERIFIED

1. **Verified requester and guardian authority:** approved process distinct from a Telegram code, known request reference, email ownership, or self-entered relationship.
2. **Full subject data mapping:** relation-by-relation, storage-by-storage and processor-by-processor ownership lookup; identify and redact unrelated persons. Produce controlled evidence of the mapping and last schema review.
3. **Legal decision and retention:** qualified Ethiopian legal/privacy and safeguarding approval per data category, including child protection, accounting, tax, dispute/incident evidence, the PDPP, cross-border hosting and backups. Record decision owners and limits; never mark an entire account automatically erasable.
4. **Approved fulfillment implementation:** authorization-scoped access/rectification/export/erasure with preflight checks, least privilege, request binding, no mass deletion, idempotency and graceful partial failures; test on isolated non-production identities.
5. **Secure disclosure/delivery:** private expiring link, verified recipient, third-party redaction, expiry/revocation, actual delivery evidence, and a mechanism for inaccessible or partial exports.
6. **Independent closure and appeals:** separate reviewer verifies actual fulfillment, captures non-sensitive outcome/exception and audit, notifies the verified recipient and records a lawful dispute/appeal route.

**Hard stop:** No production `completed`/`rejected` status transition, data export, file download, profile deletion, account deletion, or blanket retention override is authorized by this document. Existing MELA review checkpoints are attestations **only**. Do not attach identity documents or confidential free-text evidence to those checkpoint records. MELA payment collection settings are out of scope.

## Next engineering acceptance tests

- Catalog every person-linked table, indirect link, JSON payload, Auth resource, storage ownership rule, backup and external processor. Produce a **reviewed data-flow map**, with schema drift checks.
- Test a full request with **two distinct accounts**, a child/guardian case and an MFA administrator: prevent cross-account reads, false guardian claims, raw third-party export, direct cascade deletion and skipped retention; ensure audit receipts are not lost.
- Validate a controlled trial export/erasure in **isolated staging** with fabricated data and deterministic cleanup, not real customer data. Require counsel and safeguarding approval before enabling any production action.
- Approve storage location, controller identity and vendor agreements; data-location compliance remains separately unresolved.

**Reproduction:** `docs/sql/privacy_subject_metadata_inventory.sql` contains only `SELECT` queries against production schema metadata and Storage bucket configuration. This report must be refreshed after schema changes and signed off before a real fulfillment release.
