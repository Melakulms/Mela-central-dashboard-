# MELA — Privacy Request Review Procedure (draft)

**Prepared:** 3 November 2026  
**Status:** Working draft for independent Ethiopian legal/privacy and safeguarding approval. Not legal advice, not an assertion that user rights requests have been operationally certified.

## Authorized access

The live `public.data_subject_requests` table is guarded by RLS. The `private.is_admin_user()` policy currently allows an active MFA-required super administrator only when the session is at `aal2` (aside from system/service access). The admin UI exposes a restricted request queue under **Audit Log** only when the administrative permissions include `*`. The UI's permissions check is not the security boundary; database RLS is.

Do not grant broad access to child-data or rights requests for ordinary administrator roles. If additional data-protection reviewers are approved, introduce a scoped server-side authorization role with MFA and independently tested RLS before enabling access.

## Intake and triage

1. In the administrator dashboard, sign in through the dedicated admin entrance, verify the authenticator, and open **Audit Log → Personal-data rights requests**. Review the oldest pending item first.
2. Review the request category: access, export, rectification, erasure, objection or restriction. The frontend stores a pending record; it does **not** execute a deletion/export or attest identity.
3. Independently confirm the requesting user's identity and relationship to any affected learner or guardian. A Telegram registration code or an email string alone does not prove legal authority to request a child's information.
4. Review the relevant lawful basis, any safety risks, exemptions and required retention. Do not disclose third-party, child, employer or mentor personal information through a data export.
5. Route requests needing safeguarding, financial/accounting, regulatory or evidence-preservation review to the trained responsible staff under approved access controls. Never paste personal details into public GitHub issues, Telegram channels or unverified email threads.
6. **Begin review only:** for an eligible pending request, select **Inspect**, enter a 12–500 character **user-visible** review message, confirm that you are authorized, and choose **Begin review (audited)**. Do not put identity evidence, confidential staff notes or third-party details in this message. The database requires an active super administrator at `aal2`, enforces the `pending → in_review` transition, attributes the reviewer to the authenticated user, updates the timestamp, and appends a redacted event to `admin.audit_log`. A stale or cancelled request cannot be reopened by this action. This is not a final review decision.
7. **Update a case while it remains under review:** the same assigned, MFA-verified administrator can open an in-review case and select **Send review update (audited)**. Enter a new 12–500 character user-visible message, confirm the action, and submit. The database refuses identical notes, stale updates, unauthorized reviewers, users without MFA, or changes to the original request. Each progress update stores its previous/new message SHA-256 fingerprints and lengths in the restricted audit log, without copying the text into audit metadata. The previous message is replaced in the user's request view; it is not preserved as a readable conversation history. This action does **not** resolve the request.
8. **Pre-decision checkpoints (internal):** when a request is under review, the assigned MFA-verified super administrator can record structured, append-only checkpoint observations. These are staff assessments only, with no document upload, and are not independently verified evidence or permission to finalize the request. See [Pre-decision checkpoints](PRIVACY_REQUEST_PRE_DECISION_CHECKPOINTS_2026-11-03.md). The requester sees the latest review message and time, not these internal observations.
9. **Final resolution remains unavailable:** there is no completed/rejected/erased/exported button and no automatic account deletion. The completed or rejected status must not be set using manual SQL as a substitute for an approved, tested, legally reviewed workflow.
10. Send any final decision through a verified private contact channel. If the request cannot lawfully be fully fulfilled, explain the applicable reason and any available review or complaint channel, after legal review.
11. Recheck statuses until all requests are accounted for. Use the 14-day age indicator as an **internal monitoring alert**, not a statutory deadline or promise of response time.

## Escalation and security

- Erasure: assess database objects, backups, audit/legal-retention exceptions, child safeguarding evidence and third-party processor data. Never directly delete a Supabase Auth user to resolve a request without a reviewed end-to-end erasure plan. Do not turn on an automatic "delete everything" endpoint.
- Exports: validate the intended user's identity, redact unrelated users' information, use an expiring private download and log the handoff. Do not email full education or identity data as plain text.
- Rectification: check accuracy and preserve immutable compliance/financial audit information where required. Avoid overwriting other users' records.
- Restriction or objection: assess the legal basis and stop affected optional processing only after reviewing impacts on child protection and account safety.
- Suspected breach, abuse or coercion: escalate through the safeguarding/security incident route immediately, not only the ordinary rights request workflow.

## Redacted case handoff (draft, not proof of fulfillment)

Once the case is in review, open **Pre-decision review checkpoints → Redacted case handoff for authorized legal review**. The read-only summary lists the request's opaque case reference, request category, and latest available structured checkpoint observations; it **never** includes requester names, user IDs, private messages, uploaded documents, identity evidence, or fulfillment data. It shows at most the last 60 observations and may omit earlier records, so it must not be mistaken for the full case history.

On Android, use **Copy redacted handoff** or select the read-only text manually if clipboard permission is unavailable. Share only through an approved private case-management process, after confirming the recipient's authority. Never paste it into public GitHub issues, unverified Telegram chats, or public email lists. The request reference itself is pseudonymous case information and still needs careful handling.

**Important:** Even with all six checkpoint categories marked reviewed, MELA must not infer that identity, guardian authority, legal approval, Ethiopia-local data hosting, independent fulfillment evidence, or secure delivery have been proven. The admin dashboard does not expose a final-resolution, export, erase or rejection control. Genuine fulfillment still requires a separately implemented and legally approved process plus independent real-account acceptance tests.

## Remaining launch gates

- Qualified Ethiopian counsel must approve user-rights wording, access process, storage locations, cross-border safeguards, regulator registrations and statutory deadlines under Personal Data Protection Proclamation No. 1321/2024.
- MELA's current Supabase production region is **eu-west-1**. Ethiopia-local storage obligations and applicable approved transfer/processing arrangements remain unresolved. Do not mark data-hosting compliance passed.
- The **begin-review and follow-up** transitions have staging rollback-only positive and negative tests (owner cancellation, MFA administrator review, MFA reviewer follow-up, non-admin attempts, immutable field edits, AAL1 denial, and premature completion denial). No test requests or audit rows were retained.
- A **separate** counsel-approved and audited decision mechanism with independent authorization and fulfillment tests is still required before completion, rejection, information export or erasure can be enabled.
- Test with real MFA-verified super administrator and distinct non-admin/guardian/learner accounts in a permitted environment. No production sample users or personal requests should be fabricated for testing.
- Retention schedule, verified operator/privacy contact, staffing and incident response procedures must be finalized before unrestricted public launch.

## Official reference

Ethiopian Communications Authority Personal Data Protection Proclamation No. 1321/2024: https://pdp.eca.et/pdp-proclamation
