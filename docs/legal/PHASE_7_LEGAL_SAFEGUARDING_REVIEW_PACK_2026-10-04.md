# MELA Phase 7 — Legal & Safeguarding Review Pack

**Date:** 4 October 2026  
**Status:** DRAFT FOR QUALIFIED REVIEW — **not legal advice, not legal approval, not a launch certification**

This pack converts the current MELA product controls into reviewable policy language. It is intended for product, safeguarding, privacy and Ethiopian legal review before unrestricted public launch. Any conflict between this draft and applicable law, regulator guidance, provider terms or a signed contract must be resolved in favor of the authoritative requirement.

## 1. Current technical safeguarding baseline

MELA currently enforces the following product controls:

- School-stage learners are blocked at the database layer from private work-contract messaging.
- Direct mentorship is disabled for lower school stages; Grade 11–12 mentorship requires guardian verification or an adult-eligibility clearance already enforced by the server.
- Guardian consent requests are created as **pending**. Learners cannot self-verify the relationship or write verification fields.
- A learner Safety Center provides a route to submit safety reports and track their moderation status.
- Submitted report evidence is immutable; report moderation is limited to the MFA-backed admin authority and the `moderation.manage` permission path.
- Video calls remain feature-flagged OFF pending production safeguarding/media review.
- Earn & Work, payouts, challenges and payments remain feature-flagged OFF pending their respective financial/safety/provider gates.
- Existing policy acknowledgements are versioned in the database. Draft wording in this repository is not automatically active merely because it exists in source control.

These controls reduce risk but do not replace human safeguarding operations, regulatory registration, legal review, incident response staffing or real-user acceptance testing.

## 2. Ethiopian personal-data baseline for counsel review

Official references reviewed for this draft:

1. Ethiopian Communications Authority (ECA), Personal Data Protection Proclamation No. 1321/2024: https://pdp.eca.et/pdp-proclamation
2. Official proclamation PDF: https://eca.et/wp-content/uploads/2024/10/personal_data_protection_proclamation_No_1321_2024.pdf
3. ECA Personal Data Protection portal: https://pdp.eca.et/
4. ECA registration guidance: https://pdp.eca.et/blog/compliance/how-to-register-personal-data-protection-in-ethiopia
5. ECA PDP registration guide: https://pdp.eca.et/pdp-guide
6. ECA authority description: https://www.eca.et/about/

Key review points from those official sources:

- Proclamation No. 1321/2024 treats the processing of a minor's personal data as a distinct compliance area. Article 11 requires processing to protect and advance the minor's rights and best interests and provides for parent/guardian/tutor authorization or another lawful basis where applicable.
- The same minor-data provisions require reasonable efforts around age and parent/guardian/tutor consent verification where consent is relied upon. MELA's pending-versus-verified guardian state is designed to preserve that separation, but the actual verification procedure must be approved by counsel/safeguarding owners.
- ECA states that it is the national authority for personal-data protection and registers/supervises controllers and processors.
- ECA's published registration guidance states that organizations processing personal data must register before processing, and its registration workflow distinguishes controller, processor or both roles.

**OWNER_ACTION_REQUIRED:** qualified Ethiopian counsel/privacy professional must determine MELA's final controller/processor role(s), registration timing/status, lawful bases, minor-consent procedure, DPO obligations if applicable, cross-border safeguards and required regulator submissions. Engineering must not mark these items complete from code evidence alone.

## 3. Draft Terms of Service clauses

### Eligibility and account integrity

Users must provide accurate account information and use only accounts they are authorized to use. School-stage learners receive age/stage-appropriate restrictions. A user may not misrepresent age, education stage, guardian status, employer status, mentor verification or another person's identity to bypass a safety control.

### Acceptable use

Users may not use MELA to harass, threaten, exploit, sexually solicit, groom, defraud or endanger another person; obtain a minor's private contact or financial details outside an approved flow; impersonate another person; distribute malware; evade account or moderation controls; manipulate assessments; or use MELA for unlawful activity.

### Learning, AI and opportunity information

Educational, career, scholarship and AI-assisted information may contain errors or become outdated. Users remain responsible for checking consequential external requirements with the relevant institution or official source. MELA should label AI assistance and should not represent AI-generated content as qualified professional, legal, medical or financial advice.

### Account enforcement

MELA may restrict, suspend or terminate access when reasonably necessary to protect users, investigate abuse, comply with law, preserve platform integrity or enforce these terms. Serious safeguarding concerns may be escalated to authorized persons or authorities where legally required or permitted.

### Payments and paid services

Paid services are unavailable unless the relevant production feature flag is enabled after provider, legal and reconciliation acceptance. A displayed price or draft product record does not itself make a payment service available.

### Changes

Material policy changes should be versioned, dated and, when legally or operationally required, presented for renewed acknowledgement.

**OWNER_ACTION_REQUIRED:** Ethiopian counsel must review eligibility, minors' contractual capacity, limitation-of-liability language, dispute terms, governing law/jurisdiction, suspension/termination, intellectual property and all paid-service clauses before publication.

## 4. Draft Privacy Notice clauses

### Who is responsible

MELA should identify the legal entity operating the service, its contact details, privacy contact/DPO if applicable, and its ECA registration information once confirmed.

### Data categories

Depending on role and enabled features, MELA may process account/contact information; education stage and learning progress; profile and career evidence; guardian relationship information; employer/mentor verification evidence; applications and opportunities; safety/moderation reports; assessment/proctoring data where separately consented and enabled; device/security logs; and financial transaction references where paid services are enabled.

MELA should avoid collecting data merely because it might be useful later. Fields should have a documented purpose and retention rule.

### Purposes and lawful bases

Purposes should be mapped to a lawful basis approved by counsel. Typical product purposes include account creation and security, delivering learning services, safety and fraud prevention, user-requested opportunities/mentorship, compliance, and optional features for which consent is genuinely appropriate. Consent must not be presented as the legal basis when another basis is actually relied upon.

### Minors

Minor data must receive heightened protection and be processed in the child's best interests. Where parent/guardian/tutor consent is relied upon, MELA must maintain a reasonable verification procedure and must not treat a learner's own submission of guardian details as verified consent.

### Recipients and service providers

The production notice must identify or clearly categorize material processors/subprocessors such as hosting/database, email, AI and payment providers. Processing locations and cross-border transfer safeguards must be documented in the internal processing register and disclosed where required.

### Retention and deletion

Each major data category should have a retention period or defensible retention criterion. Safety evidence, financial records and legal/audit records may require different retention from ordinary profile data. Deletion requests must be handled consistently with legal retention obligations and security/fraud requirements.

### User rights

The final notice must accurately describe applicable access, correction, deletion/erasure, objection/restriction, portability or complaint rights under Ethiopian law and provide a workable request channel. Do not promise a right or response period that operations cannot meet.

### Security and incidents

MELA should describe security at an appropriate level without publishing exploitable detail. Incident and breach notification procedures must be aligned with the proclamation and current ECA guidance.

**OWNER_ACTION_REQUIRED:** counsel/privacy reviewer must approve the processing inventory, lawful bases, retention schedule, data-subject rights wording, cross-border transfer position, breach duties, child-data language and ECA disclosures.

## 5. Draft Child Safeguarding & Community Safety Policy

### Core principles

1. The child's rights and best interests take priority over engagement or monetization goals.
2. Adults must not use MELA to seek secret, sexual, coercive, exploitative or financially manipulative relationships with minors.
3. School-stage learners must not be moved into unrestricted private work messaging.
4. Guardian status must be verified by an authorized workflow; learners cannot self-certify it.
5. Reports involving sexual exploitation, grooming, credible threats, self-harm crisis or serious abuse require an explicit high-priority response path rather than ordinary content-moderation handling alone.

### Reporting

Users should be able to report bullying/harassment, unsafe contact, sexual/exploitative content, privacy/identity concerns, fraud/scams, self-harm/crisis concerns and other safety issues. Reports must be visible only to the reporter and authorized moderators, apart from service/admin roles needed for operation. Evidence fields should remain immutable after submission.

### Moderator procedure

Moderators should record a status and reason, preserve evidence, avoid unnecessary disclosure of a reporter's identity, and use a defined escalation matrix. Terminal decisions should notify the reporter at a level of detail that does not compromise another person's privacy or an investigation.

### Emergency limitation

MELA reporting is not an emergency response service. The product should direct a person in immediate danger toward a trusted adult and appropriate local emergency or protection resources. The final production wording and local resources should be reviewed by a qualified safeguarding professional in Ethiopia.

**OWNER_ACTION_REQUIRED:** appoint a safeguarding owner; approve severity/escalation SLAs; define emergency/local referral resources; establish law-enforcement/regulator request procedures; train moderators; run human abuse-case testing with minor-safety specialists.

## 6. Draft Mentor Safeguarding Agreement

A mentor must:

- use only approved MELA communication/session channels for MELA mentorship;
- avoid requesting secrecy, intimate/sexual communication, money, gifts, passwords, financial credentials or unnecessary private contact details from a learner;
- respect education-stage and guardian restrictions;
- avoid discriminatory, abusive, humiliating, coercive or exploitative conduct;
- report credible safeguarding concerns through the approved channel;
- keep learner information confidential and use it only for the mentorship purpose;
- understand that verification may be suspended or revoked when safety or identity requirements are not met.

Mentor verification is not a guarantee of character, professional qualification or future conduct. The verification standard, background-check requirements if any, and consequences must be defined and legally reviewed before publication.

**OWNER_ACTION_REQUIRED:** qualified safeguarding/legal review of mentor eligibility, identity evidence, vetting, code of conduct, incident duties and record retention.

## 7. Draft Employer Agreement safeguards

Employers using MELA must:

- provide accurate organization and opportunity information;
- not solicit unlawful child labor or bypass education-stage/work restrictions;
- not ask learners to move to unapproved private channels to evade MELA safeguards;
- collect only applicant information necessary for the stated opportunity;
- use applicant data only for legitimate recruitment/engagement purposes and secure it appropriately;
- comply with applicable labor, anti-discrimination, child-protection, tax, data-protection and sector requirements;
- not demand payment from a learner in exchange for a purported job, internship or opportunity unless a lawful, disclosed program explicitly permits a fee and MELA has approved the flow;
- cooperate with fraud/safety investigations and preserve relevant evidence.

**OWNER_ACTION_REQUIRED:** Ethiopian employment/labor counsel must review minor work eligibility, internship/apprenticeship rules, employer data-controller obligations, sector restrictions and contract terms.

## 8. Draft Content & Education Quality Policy

- AI- or machine-generated learning content must not be treated as educator-approved merely because it passes automated checks.
- Credential-bearing assessment content requires the defined educator and language certification gates.
- Translation availability and translation certification are separate states.
- Corrections should preserve a review/audit record when the content has already affected learners or credentials.
- Sponsored/employer content should be distinguishable from independent learning content.

Human editorial, educator and language review remains required for the pending launch gates; no source-control change can substitute for those approvals.

## 9. Draft Refund & Paid-Service Policy framework

Payments are currently disabled. Before enabling any paid service, the published policy must state at minimum:

- the exact seller/merchant identity;
- price, currency and billing period before purchase;
- what constitutes successful delivery/activation;
- cancellation rules for recurring services;
- refund eligibility and exclusions consistent with applicable law and provider rules;
- duplicate/failed/incorrect-amount handling;
- method and expected operational path for refund requests;
- treatment of provider fees, chargebacks and disputes;
- contact/escalation channel;
- how account suspension affects prepaid access where legally permitted.

Do not publish specific refund timelines or guarantees until the merchant/provider workflow can actually meet them.

**OWNER_ACTION_REQUIRED:** payment-provider contracts and Ethiopian consumer/legal review before any paid flag is enabled.

## 10. Data-processing and cross-border register checklist

For every material processor/subprocessor, record:

- legal name and service;
- controller/processor role;
- data categories and data-subject groups, including whether minors are involved;
- purpose and lawful basis;
- processing/storage locations;
- transfer mechanism/safeguard and contractual terms;
- retention/deletion commitments;
- security/contact details;
- incident notification obligations;
- effective contract/DPA version and review date.

At minimum, production review should cover Supabase, AI/model providers used by MELA, transactional email, analytics/monitoring, any media/video provider, and payment providers before those features are enabled.

## 11. Release gate

Phase 7 engineering can be considered implemented only at the product-control level when reporting, moderation, guardian controls, minor communication restrictions and user-facing safety routes are tested and deployed. **Phase 7 legal certification remains NO-GO** until:

- ECA/controller-processor registration status is resolved;
- Ethiopian counsel approves Terms, Privacy, child-data, employer/mentor and payment/refund terms;
- a qualified safeguarding reviewer approves the child-protection operating procedure;
- cross-border processing/transfer safeguards and DPAs are recorded;
- real-user child-safeguarding abuse tests pass in the hosted environment;
- trained human moderators and escalation ownership exist.

`OWNER_ACTION_REQUIRED` remains the correct state for those external/legal gates.
