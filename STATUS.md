# MELA delivery status

Updated: 4 October 2026, Africa/Addis_Ababa. Decision: **NO-GO for unrestricted public or paid launch**.

Phase 1 audit is complete at inventory/targeted-inspection depth. Phase 2 remains open. Phase 3 safety repairs are implemented; Phases 4 and 5 are actively being hardened at the owner’s request. Phases 3–11 are not certified. A code audit is not a real-user pilot, payment-provider certification, legal approval, or capacity proof.

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
| Security | RLS coverage 2; privileged authorization 1; financial safety 1; independent/security acceptance 0 | 50% | Authenticated SECURITY DEFINER advisor inventory is now 90; leaked-password protection remains disabled |
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
- The Supabase authenticated privileged-function advisor inventory has continued to fall through targeted invoker-wrapper conversions; it is now 90. Anonymous exposure remains the single intentional certificate verifier. Remaining privileged-function review, historical schema/source reconstruction and external configuration gates prevent Phase 2 certification. See docs/audit/PHASE_2_SECURITY_2026-10-04.md.

## Owner actions and stop conditions

OWNER_ACTION_REQUIRED: provide provider-issued sandbox onboarding/documentation and credentials through secure configuration for telebirr and CBE Birr; configure/verify public transactional SMTP and a sender domain when budget permits; enable supported leaked-password protection; select/control the production domain; appoint qualified content/translation/safeguarding reviewers and Ethiopian legal counsel; supply the canonical 53-field curriculum if not present elsewhere; arrange the school pilot and consent. These are dependencies, not completed actions. No unrestricted public launch date is committed until release gates pass.

Financial gates must remain disabled. No synthetic provider success, fake content approval, fabricated pilot, or self-issued external certification counts as evidence. The zero-budget invite-only beta may continue independently of the unrestricted public-launch decision.

## Latest Phase 2 checkpoint — video boundary and recovery archive

- Applied and regression-tested database enforcement of video shutdown. Create/invite/rejoin/recording/signaling/presence are blocked while disabled; leave/end cleanup remains available. Financial and video feature flags remain disabled.
- Archived all 607 recorded migrations with checksums and an integrity verifier. This is recovery source material, not a backup/restore certification: the oldest recorded migration depends on an earlier, missing baseline.
- Current advisor snapshot in that checkpoint was 94 authenticated privileged-function warnings; subsequent Phase 4/5 wrapper hardening reduced the live count to 90. Individual authorization review and leaked-password protection remain open. Readiness percentages above remain conservative; no restore credit was added merely for recovering SQL.
- `supabase/recovery/README.md` records the isolated restore procedure and missing baseline/staging prerequisites. Phase 2 remains in progress. Phases 3–11 remain subject to the ordered acceptance gates.

## Phase 3 checkpoint — admin authority and MFA

- Reproduced and fixed a legacy authorization regression: a profile label alone could grant generic admin authority. Only an active Central Admin super admin with an active profile and AAL2 now gets that override; other roles use permission-specific APIs.
- Applied migration `20261004103224_restore_central_super_admin_legacy_boundary`. Active admin records must require MFA.
- Fixed double-encoded authenticator QR images, duplicate verification submissions, failed refresh handling and stale enrollment callbacks. No real authenticator acceptance is claimed.
- Validation: 57 admin automated tests and production build passed; live rollback tests for legacy override, registry authority, atomic admin updates and user journeys passed.
- See `docs/audit/PHASE_3_ADMIN_CERTIFICATION_2026-10-04.md` for all 23 gates. Percentages remain unchanged because broader acceptance is still missing.

## Phase 4 checkpoint — escrow callback verification

- Phase 3 release `4f3c8ce` published; Admin CI run 37212150488 and Pages run 37212150518 passed.
- Recovered deployed `mela-finance-callback` version 4 into the recovery directory and checked the maintained callback into version control. Version 5 is deployed with signature authentication preserved.
- Fixed live/test mode mismatch acceptance, rounding of invalid amount precision, late callback status downgrades, and acknowledgement of provider verification outages. Finalization still uses the existing atomic, idempotent database function.
- Added 19 isolated callback tests; total admin suite is 76 passing tests, with production build passing. These use synthetic local fixtures and are not provider sandbox certification.
- Payments, payouts, earn_work and video flags were read back as false. Readiness scores remain unchanged; see `docs/audit/PHASE_4_PAYMENTS_2026-10-04.md` for current limitations and provider onboarding gates.
- Live callback smoke: GET 405, unsigned POST 503 (webhook verification unavailable). Configure the provider webhook secret securely before signed sandbox testing; no secret was read or changed.

## Phase 4 continuation — finance and course verification

- Previous release `c5f5e91`: Admin CI and GitHub Pages both completed successfully.
- Found deployed `mela-finance` version 5 lagging behind repository authorization fixes. Deployed version 6 removes profile-label admin access to unrelated employers, adds exact transfer/escrow amounts, checks attempt environment, and restricts delayed updates to unfinished attempts. JWT verification remains enabled; unauthenticated live smoke returned 401.
- Recovered six additional deployed checkout/course-payment sources. Hardened and deployed course verification: `chapa-verify` v4, `chapa-callback` v6, `mela-learning-payment-verify` v3, `mela-learning-payment-callback` v7. Manual verification checks Auth identity and scopes payment lookup to that user; callbacks retain HMAC verification. All four reject invalid amounts/modes and provider outages safely.
- Validation: 164 automated tests pass across eleven suites; production frontend build passes. No provider sandbox payment or signed live event was performed. Tests simulate provider/database responses, so concurrent database acceptance remains open.
- Read back payments/payouts/earn_work/video flags: all false. No readiness percentage increased and Phase 4 remains in progress.

## Phase 4/5 continuation — checkout initiation and mentorship ratings

- Deployed `chapa-initialize` v5 and `mela-learning-checkout` v3. Both now revalidate Auth identity, enforce test/live key-mode agreement, derive prices server-side, reuse matching pending checkouts, apply provider timeouts and condition state updates on `initiated` attempts only. Their previously missing maintained sources are now version-controlled.
- Rechecked authoritative subscription pricing: normal/registration access is 20 ETB, Premium is 50 ETB; referral configuration is 10 ETB / 20 ETB. The active auth invitation trigger uses the tier-aware referral path. Payment flags remain OFF.
- Applied `20261004162514_complete_mentorship_ratings_and_wrapper_hardening`: one rating per completed mentorship session, participant-only RLS, mentor aggregate rating/count, notification, MFA-backed mentor-profile admin policies, and invoker wrappers for four lifecycle RPCs.
- Applied `20261004162626_repair_shared_role_profile_verification_guard` after rollback testing exposed a stale call to removed `public.is_admin_user()`. The shared company/teacher/mentor/educator verification guard now uses `private.is_admin_user()`.
- Rollback-only mentorship rating regression passes: valid mentee rating succeeds; duplicate/outsider/direct-write attempts fail; aggregate refresh is correct. No fixtures persisted.
- Learner PR #25 adds the rating UI and test. Admin/backend PR #26 contains payment source recovery, migrations, regression and evidence. CI must be green before merge.
- See `docs/audit/PHASE_4_5_CONTINUATION_2026-10-04.md`. Readiness percentages remain conservative because provider sandbox, reconciliation, real-user E2E, human content/translation review and other launch gates are still open.
