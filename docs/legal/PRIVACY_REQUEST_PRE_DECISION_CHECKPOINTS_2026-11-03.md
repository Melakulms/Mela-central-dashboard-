# MELA privacy request — pre-decision review checkpoints

**Status:** Draft operating procedure, 3 November 2026. Requires trained administrator, safeguarding lead and Ethiopian legal counsel review. This is a record of staff observations, not independent proof, a final legal determination or an authorization to erase/export a person's information.

## Why the checkpoints exist

MELA's verified super administrator can begin a privacy request review and send a user-visible update. Before decisions, there must be a controlled way to record whether different concerns have been considered. The `privacy_review_checkpoints` table stores *append-only*, minimal structured observations, tied to an open request and the authenticated assigned reviewer. It stores **no** identity document, name, phone number, payment reference, school record, long text note or file.

Possible finding for each checkpoint:
- **Needs additional verification or action:** the matter is not ready to move forward
- **Reviewed — no issue identified:** an accountable staff member reports reviewing that concern; this is **not** an automated check or an assertion of legal compliance

Six checkpoint types: account-holder identity, verified guardian authority if applicable, scope/third-party privacy, lawful basis and retention, child safeguarding/incident context, and secure fulfillment planning. A non-applicable step may still require a human rationale outside this structured form. The dashboard displays the most recent 60 entries, which may omit older categories; the full immutable record remains in the database and audit events.

## Administrator workflow (Android-friendly)

1. Sign in to MELA Central Admin with an active super-admin account and Google Authenticator. Open **Audit Log → Personal-data rights requests**.
2. Open an existing request and verify the requester using the organization's *approved private process*. Do not use a Telegram chat, email address, or guardian contact alone as proof of a child's legal guardian.
3. If pending, choose **Begin review (audited)** and enter a safe message to the requester. Do **not** mark the request complete.
4. Open **Pre-decision review checkpoints** for an `in_review` request. Only the assigned MFA-verified super administrator can insert observations.
5. Select a checkpoint and an observation. Confirm that you personally evaluated it. Select **Record checkpoint (audited)**.
6. The checkpoint entry records category, observation, reviewer and server time. The audit log records its event and reference. It does not retain private evidence or a claim that an outside authority approved it.
7. For new information, add another entry. Previous entries cannot be rewritten or deleted through the application. If a concern requires more work, leave the case `in_review`, escalate via an approved private procedure and inform the requester with a safe progress message.
8. Final completion, rejection, data export, deletion, compensation and formal legal authorization **are not available** in this workflow.

## Technical security and negative tests

- Database RLS: authenticated user AND active super administrator AND MFA `aal2` to read; also assigned reviewer, `in_review` request and same `auth.uid()` to insert.
- Database BEFORE INSERT trigger enforces active assignment/MFA again, overwrites client-generated IDs and timestamps, and writes an audit event without documents or free text.
- No `UPDATE` or `DELETE` privileges for signed-in accounts. No corresponding RLS policies.
- Tested in staging using rolled-back SQL transactions: assigned AAL2 reviewer can record and audit a checkpoint; the requester cannot read/insert; an AAL1 administrator cannot read/insert; signed-in users cannot modify an existing entry.
- Final-resolution and fulfillment gates remain blocked. There is no new mass-deletion endpoint or import of user records.

## Before lawful fulfillment can be enabled

A qualified Ethiopian reviewer must approve identity/guardian verification standards, rights and exemptions, data residency/local-hosting requirements, evidence preservation and retention schedules, legal basis for disclosure, official privacy contact, and secure communications. Independently test live account flows with permission, including reviewers, minors, guardians, denial and appeals. A staff checkbox cannot replace proof of fulfillment.

The production database has historically been hosted outside Ethiopia; legal and technical resolution is still open.

Official legislation reference: https://eca.et/wp-content/uploads/2024/10/personal_data_protection_proclamation_No_1321_2024.pdf
