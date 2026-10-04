# MELA delivery status

Updated: 4 October 2026, Africa/Addis_Ababa. Decision: **NO-GO for unrestricted public or paid launch**.

Phase 1 audit is complete at inventory/targeted-inspection depth. Phase 2 is in progress. Phases 3–11 are not certified. A code audit is not a real-user pilot, payment-provider certification, legal approval, or capacity proof.

## Evidence-based readiness

These are conservative engineering assessments, not measured percentages of all project work. Each layer has four gates scored 0 (absent/unverified), 1 (partially implemented/verified), or 2 (verified at the stated scope). Percentage = points / 8, rounded. Unknowns receive no completion credit. Gates are equally weighted for transparency; one critical blocker overrides the percentage.

| Layer | Four gate scores, in order | Readiness | Blocking evidence |
|---|---|---:|---|
| Database | schema 1; role isolation 2; reproducible migrations 0; financial invariants 1 | 50% | 599+ live migration records include recoverable SQL; fresh reconstruction unproven; coin/private-RLS/badge repairs tested |
| Auth | login/onboarding 1; MFA/RBAC 1; email/recovery 0; session boundaries 1 | 38% | Zero-budget invite beta works, but real public SMTP/recovery and full MFA user E2E are not certified |
| Admin | operational UI 1; permissions 1; audited mutations 1; certification 1 | 50% | MFA admin observability/proctor reads now use invoker wrappers with negative and positive authorization tests; full 23-gate certification absent |
| Frontend | routes 1; data contracts 1; recovery 2; complete user journeys 0 | 50% | Automated suites/deploy smokes pass, but no full role-by-role production E2E |
| Payments | provider implementation 0; webhook/replay 1; reconciliation 0; sandbox acceptance 0 | 13% | Existing Chapa code differs from required telebirr/CBE Birr; financial flags remain disabled |
| Content | catalog 1; complete lessons 1; educator approval 0; five-language certification 0 | 25% | Qualified educator chapter/question review workflows now exist, but human approvals/certification remain incomplete; 53-field canonical curriculum not identified |
| Security | RLS coverage 2; privileged authorization 1; financial safety 1; independent/security acceptance 0 | 50% | Authenticated SECURITY DEFINER advisor inventory reduced 112→101 with negative authorization tests; leaked-password protection disabled |
| Testing | unit/component 2; SQL negative tests 1; real-user E2E 0; capacity/restore 0 | 38% | Rollback-only authorization/invariant tests pass; no 5,000-user or restore evidence |
| Deployment | Pages CI 2; desired domain/public mail 0; staging 0; monitoring/rollback 1 | 38% | GitHub Pages pipelines exist; custom domain/public SMTP and disposable staging/restore are not certified |

See [full audit](docs/audit/FULL_AUDIT_2026-10-04.md) for module status, evidence, build order and owner actions. Do not copy older release-document counts as current truth.

## Work ledger

- Consumer fixes published as 76fb503; main checks and Pages deployment run 37158029971 succeeded. Admin audit/security release published as 8097a25; CI and Pages deployment run 37158517683 both passed.
- Live security and performance advisors inspected. Public/admin RLS coverage confirmed; financial/video/challenge flags remain disabled where previously disabled.
- Phase 2: private-table RLS, four foreign-key indexes, coin invariants and badge counters repaired. Existing rollback-only SQL regressions pass. Both production dependency audits report zero known vulnerabilities; admin tests/build passed.
- Zero-budget qualified educator workflows are now present for chapter review, question-review slices and assessment-language review. Teacher approval and reviewer subject authorization remain server-enforced; no human approval was fabricated.
- `20261004040739_harden_question_review_read_wrappers` converted the question-review queue/slice public endpoints from SECURITY DEFINER to SECURITY INVOKER while retaining private caller/subject checks. `20261004041220_harden_question_reviewer_capability_wrapper` did the same for reviewer capability. Student negative tests remain closed.
- `20261004041516_harden_admin_observability_read_wrappers` converted launch-readiness and operational-health public endpoints to invoker wrappers backed by private MFA-admin checks. `20261004041714_harden_proctor_review_queue_wrapper` moved the proctor queue's privileged table reads into a private implementation and left an invoker wrapper public. Non-admin/AAL1 paths are denied; a registered AAL2 admin path succeeds.
- `20261004042011_harden_read_only_api_wrappers` converted five more wrapper-only reads to SECURITY INVOKER: data-protection compliance pack, learner question overview, question catalog, educator quality progress and question subject detail. Learner-safe reads still work; restricted educator/admin reads stay closed to learners; AAL2 admin checks pass.
- The Supabase authenticated privileged-function advisor count fell from 112 to 101; anonymous exposure remains the single intentional certificate verifier. Remaining privileged-function review, historical schema/source reconstruction and external configuration gates prevent Phase 2 certification. See docs/audit/PHASE_2_SECURITY_2026-10-04.md.

## Owner actions and stop conditions

OWNER_ACTION_REQUIRED: provide provider-issued sandbox onboarding/documentation and credentials through secure configuration for telebirr and CBE Birr; configure/verify public transactional SMTP and a sender domain when budget permits; enable supported leaked-password protection; select/control the production domain; appoint qualified content/translation/safeguarding reviewers and Ethiopian legal counsel; supply the canonical 53-field curriculum if not present elsewhere; arrange the school pilot and consent. These are dependencies, not completed actions. No unrestricted public launch date is committed until release gates pass.

Financial gates must remain disabled. No synthetic provider success, fake content approval, fabricated pilot, or self-issued external certification counts as evidence. The zero-budget invite-only beta may continue independently of the unrestricted public-launch decision.

## Latest Phase 2 checkpoint — video boundary and recovery archive

- Applied and regression-tested database enforcement of video shutdown. Create/invite/rejoin/recording/signaling/presence are blocked while disabled; leave/end cleanup remains available. Financial and video feature flags remain disabled.
- Archived all 607 recorded migrations with checksums and an integrity verifier. This is recovery source material, not a backup/restore certification: the oldest recorded migration depends on an earlier, missing baseline.
- Current advisor snapshot: 94 authenticated privileged-function warnings; individual authorization review and leaked-password protection remain open. Readiness percentages above remain conservative; no restore credit was added merely for recovering SQL.
- `supabase/recovery/README.md` records the isolated restore procedure and missing baseline/staging prerequisites. Phase 2 remains in progress. Phases 3–11 remain subject to the ordered acceptance gates.
