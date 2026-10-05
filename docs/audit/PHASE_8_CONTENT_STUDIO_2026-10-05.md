# Phase 8 Content Studio checkpoint — 5 October 2026

Status: **engineering foundation implemented; content certification remains pending.**

This checkpoint deliberately does not convert the owner's request to “mark human review pass” into reviewer evidence. Qualified educator, language, accessibility, safeguarding and legal approvals remain evidence-based gates.

## Live catalog truth

- 149 active learning programs.
- 887 chapter records; 887 currently published by status, but **0 are marked source_verified**.
- 142,396 active question-bank records; **0 are educator_verified**.
- 23 active programs have neither a chapter nor a question record.
- Chapter review queue: 887 pending/in-review/submitted; 0 approved.
- Pending chapter-material translations: 10,384 each for Amharic, Afaan Oromo, Tigrinya and Somali.
- Pending learning-material translations: 10,847 each for Amharic, Afaan Oromo, Tigrinya and Somali.

These counts describe inventory, not educational quality or language acceptance.

## Implemented in this checkpoint

### Versioned Content Studio storage

Migration `20261005065833_phase8_content_studio_foundation` adds service-only `admin.content_drafts` and `admin.content_draft_versions`. Every draft change creates an immutable version snapshot. Published drafts cannot be silently reverted into an editable state; a later revision must be represented as a new draft/version path.

The draft model supports chapter, material, question, translation, book and program-seed work in English, Amharic, Afaan Oromo, Tigrinya and Somali. Draft, submitted, approved, rejected, published and archived states are represented, but the administrative function shipped in this checkpoint intentionally exposes **no `draft.approve` or `draft.publish` action**.

### Inventory and gap views

Admin-only security-invoker views provide:

- per-program chapter/question inventory and empty-program detection;
- translation counts by source, language and review status;
- aggregate content-quality counts including source verification, educator verification and chapter review state.

Browser roles have no table/view grants. The service-role-backed admin function is the operational access path.

### MFA/permission-gated content administration

New Edge Function `mela-content-admin` version 1 is deployed with JWT verification enabled. It requires:

1. a valid authenticated bearer token;
2. active membership in `admin.admin_users`;
3. AAL2 whenever MFA is required;
4. super-admin status or `content.manage`.

It provides inventory, draft listing, versioned draft save, submit-for-review, archive and version-history actions. It records draft changes in the admin audit log. Submission explicitly returns `publication_locked=true` and says qualified review evidence is required.

### Admin UI

The Central Admin moderation area now contains a Content Studio for administrators with `content.manage`. It shows:

- live program/chapter/question/translation metrics;
- the empty-program queue;
- pending translation inventory;
- read-only qualified-review queue summaries;
- a structured versioned draft editor;
- submit, archive and version-history controls.

The UI has no publish/approve control.

## Verification

A rollback-only production database regression passed:

- created draft starts at version 1;
- edit increments to version 2;
- submit increments to version 3;
- exactly three immutable snapshots are recorded;
- a published draft cannot be reverted to draft;
- transaction was rolled back, so no test fixture persisted.

Automated repository tests also assert the MFA/content permission boundary, absence of admin auto-publish/auto-approve actions, optimistic version checks, service-only grants and security-invoker inventory views.

Supabase security advisor after the migration reports the two new admin tables only as `rls_enabled_no_policy` informational findings. This is intentional for server-only admin storage: RLS is enabled and all browser grants are revoked. Existing project-wide findings remain: 90 authenticated SECURITY DEFINER warnings, the intentional public certificate verifier warning, and leaked-password protection disabled.

## Still required before Phase 8 certification

- Supply/confirm the canonical ordered 53-field AI Professional Education Program; it is not identifiable from the existing 149-program catalog and must not be invented.
- Produce complete lesson bodies for the 23 empty programs and verify curriculum/source rights.
- Complete qualified educator review for chapters/questions; current approved/verified counts are zero.
- Complete native-language review for required translations; current translated material rows are pending, not approved.
- Verify accessibility, Ethiopian contextual relevance, quiz correctness, low-bandwidth rendering and learner navigation on hosted real-user flows.
- Publish accepted content only after the corresponding qualified review evidence exists.

Phase 9 must not be considered certified based on generated content alone. AI automation may assist drafting, but cannot manufacture the human evidence required by Phase 8.
