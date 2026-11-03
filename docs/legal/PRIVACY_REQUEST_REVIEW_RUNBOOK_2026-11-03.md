# MELA — Privacy Request Review Procedure (draft)

**Prepared:** 3 November 2026  
**Status:** Working draft for independent Ethiopian legal/privacy and safeguarding approval. Not legal advice, not an assertion that user rights requests have been operationally certified.

## Authorized access

The live `public.data_subject_requests` table is guarded by RLS. The `private.is_admin_user()` policy currently allows an active MFA-required super administrator only when the session is at `aal2` (aside from system/service access). The admin UI exposes a read-only request queue under **Audit Log** only when the administrative permissions include `*`. The UI's permissions check is not the security boundary; database RLS is.

Do not grant broad access to child-data or rights requests for ordinary administrator roles. If additional data-protection reviewers are approved, introduce a scoped server-side authorization role with MFA and independently tested RLS before enabling access.

## Intake and triage

1. In the administrator dashboard, sign in through the dedicated admin entrance, verify the authenticator, and open **Audit Log → Personal-data rights requests**. Review the oldest pending item first.
2. Review the request category: access, export, rectification, erasure, objection or restriction. The frontend stores a pending record; it does **not** execute a deletion/export or attest identity.
3. Independently confirm the requesting user's identity and relationship to any affected learner or guardian. A Telegram registration code or an email string alone does not prove legal authority to request a child's information.
4. Review the relevant lawful basis, any safety risks, exemptions and required retention. Do not disclose third-party, child, employer or mentor personal information through a data export.
5. Route requests needing safeguarding, financial/accounting, regulatory or evidence-preservation review to the trained responsible staff under approved access controls. Never paste personal details into public GitHub issues, Telegram channels or unverified email threads.
6. Document a reasoned decision in an approved audited case-management workflow when available. At present this admin UI is **read-only** and deliberately does **not** provide a mutation action. Do not claim a request is complete simply because it appears in this queue.
7. Send the decision through a verified private contact channel. If the request cannot lawfully be fully fulfilled, explain the applicable reason and any available review or complaint channel, after legal review.
8. Recheck statuses until all requests are accounted for. Use the 14-day age indicator as an **internal monitoring alert**, not a statutory deadline or promise of response time.

## Escalation and security

- Erasure: assess database objects, backups, audit/legal-retention exceptions, child safeguarding evidence and third-party processor data. Never directly delete a Supabase Auth user to resolve a request without a reviewed end-to-end erasure plan. Do not turn on an automatic "delete everything" endpoint.
- Exports: validate the intended user's identity, redact unrelated users' information, use an expiring private download and log the handoff. Do not email full education or identity data as plain text.
- Rectification: check accuracy and preserve immutable compliance/financial audit information where required. Avoid overwriting other users' records.
- Restriction or objection: assess the legal basis and stop affected optional processing only after reviewing impacts on child protection and account safety.
- Suspected breach, abuse or coercion: escalate through the safeguarding/security incident route immediately, not only the ordinary rights request workflow.

## Remaining launch gates

- Qualified Ethiopian counsel must approve user-rights wording, access process, storage locations, cross-border safeguards, regulator registrations and statutory deadlines under Personal Data Protection Proclamation No. 1321/2024.
- MELA's current Supabase production region is **eu-west-1**. Ethiopia-local storage obligations and applicable approved transfer/processing arrangements remain unresolved. Do not mark data-hosting compliance passed.
- A dedicated audited decision mechanism and negative/positive authorization tests are required before administrative status transitions can be enabled.
- Test with real MFA-verified super administrator and distinct non-admin/guardian/learner accounts in a permitted environment. No production sample users or personal requests should be fabricated for testing.
- Retention schedule, verified operator/privacy contact, staffing and incident response procedures must be finalized before unrestricted public launch.

## Official reference

Ethiopian Communications Authority Personal Data Protection Proclamation No. 1321/2024: https://pdp.eca.et/pdp-proclamation
