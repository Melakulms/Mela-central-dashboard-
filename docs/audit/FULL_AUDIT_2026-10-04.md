# MELA phase 1 audit

Audit date: 4 October 2026 (Addis Ababa). Scope: both current repositories, live Supabase schema metadata and advisors, migrations, function inventory, frontend/API sources, existing regression and deployment configuration. This is a complete inventory against the supplied requirements, with targeted code inspection; it is not exhaustive execution of every branch.

## Baseline and critical findings

Consumer remote main: af914f7b30ae8fe34a96e30ce9fd421c8ea9d3db. Admin remote main: 375efd78a7adecb2f635243666dc7299728071e7. Local tested follow-up fixes exist but were not on remote main at audit start.

Live project: duizgtmbptmlbyipreqg. 259 public tables and seven admin tables all enable RLS. Twelve of sixteen private tables do not; no anon/authenticated/PUBLIC direct private-table grants were found. Private RLS remains a defense-in-depth gap, not evidence of public exposure. Do not grant all roles access simply to remove no-policy notices.

597 migration records exist live; only 57 migration files are in the admin checkout. This does not yet establish exact missing-file count across both repositories, but clean reconstruction is not demonstrated. Fifty Edge Functions are deployed, while this admin checkout contains four function source directories. Import and review omitted deployed sources before claiming reproducible releases.

Security advisor: 112 authenticated SECURITY DEFINER notices, one anonymous notice, eleven no-policy INFO notices, leaked-password-protection WARN. The anonymous certificate-verification endpoint is intentional but still requires privacy regression coverage. No ERROR-level advisor item appeared. WARN is not synonymous with a demonstrated exploit; individually review callable privileged functions.

Performance advisor: four unindexed foreign keys and 241 unused-index INFO notices. Do not delete indexes merely because a pre-launch workload has not used them.

The coin ledger contains zero rows. Its insert trigger fails: it runs with empty search_path yet updates unqualified `profiles`. Reproduced with rollback-only fixtures. No append-only trigger or transaction replay index was present in the inspected ledger. Badge counter updates cover insertion/deletion but omit badge ownership updates. Registration referrals already have a unique registered-user constraint; active commissions have a partial unique registered-user index. Payments have a unique tx_ref, but a provider constraint currently permits only Chapa.

The current deployment configuration publishes both frontends on GitHub Pages. An admin netlify.toml exists; that file and a deployed Netlify relay function do not prove an active Netlify production site. Consumer Vite base is /mela-app/. Hosting migration needs an explicit base-path and redirects check.

## Module and feature inventory

Status: done = narrowly verified item; partial = implementation exists with incomplete requirements/evidence; missing = required implementation/evidence not found; broken = reproduced defect. Risk: critical/high/medium. Evidence paths are relative to consumer (C) or admin (A) repo.

| Module / feature | Status | Risk | Evidence and next fix |
|---|---|---|---|
| Signup, login, role onboarding | Partial | High | C auth.ts, Register, Login, RoleProfileSetup; beta invite/recovery path exists; verify real accounts and paid-registration transition |
| Email verification/reset via Brevo | Partial | High | C VerifyEmail/ResetPassword; live SMTP and recovery gates pending; verify domain/sender and delivery |
| Profile edits and trust fields | Partial | High | A role/trust migrations and SQL tests; complete per-role negative matrix |
| Identity verification | Partial | High | Verification fields/workflows exist; actual identity evidence, retention and operator process not certified |
| Career Passport badges | Partial | High | C CareerPassport/passport.ts; badge trigger omits UPDATE; repair counter and test reassignment |
| Course certificates/public verification | Partial | Medium | C CertificateVerification, A course_credentials.sql; test real completed learner journey and export/sharing |
| Skill Academy enrollment/player/progress | Partial | High | C SkillAcademy/CourseReader, server completion migration; paid enrollment and content review not complete |
| 53-field AI Professional Education Program | Missing | High | No canonical 53-field list found in inspected repos/program kinds; locate/obtain syllabus before inventing field order |
| Opportunity posting/review | Partial | High | C EmployerPortal, A employer_reviews.sql; repaired owner policies and approval path; test real verified employer |
| Student applications/status/matching | Partial | Medium | C opportunities.ts/OpportunityHub; test lifecycle, stale offers and matching quality |
| Scholarship discovery/saved/checklists | Partial | Medium | C EthioScholarConnect; external links are not proof of application submission; verify source freshness |
| Arena/gamified Q&A | Partial | High | C Arena; SQL matchmaking/full-round fixes; timed two-player browser, anti-cheat and settlement pending |
| Sponsored challenges/teams/prizes | Partial | High | C LearnerSubsections; disabled live; team and prize lifecycle incomplete |
| Practice/question bank | Partial | High | C Practice/QuestionBank, answer-key isolation; qualified review and full content QA pending |
| Verified assessments/proctoring | Partial | High | C VerifiedAssessments, A assessment SQL tests; real-user consent/device/credential acceptance pending |
| Books/study materials | Partial | Medium | C StudyMaterials; entitlement-aware reader; rights/source/language/completeness review pending |
| Mentorship booking/cancellation/sessions | Partial | High | C Mentorship/MentorLifecycle; backend lifecycle tests; real sessions, ratings and safeguarding acceptance pending |
| Marketplace listings/proposals/contracts | Partial | High | C LearnerSubsections/contracts.ts; financial gate disabled; test award/accept/deliver/review end to end |
| Escrow/refunds/disputes | Partial | Critical | A mela-finance and disputes tests; holds exist; dedicated resolution/reconciliation/refund settlement incomplete |
| Coin ledger | Broken | Critical | Live trigger failure reproduced; add qualified atomic update, append-only and idempotency safeguards |
| Referral commissions | Partial | High | Config 10/20 ETB confirmed; uniqueness/self-referral constraints exist; paid-event eligibility, devices/rate limits/payouts not certified |
| Registration 20 ETB / premium 50 ETB | Partial | High | Beta access enabled; required direct provider checkout not implemented; do not start charging without sandbox approval |
| telebirr direct adapter | Missing | Critical | Existing checkout is Chapa; obtain merchant contract/docs/sandbox before implementation |
| CBE Birr direct adapter | Missing | Critical | No direct adapter found; same provider prerequisites |
| Webhook signatures/amount/replay | Partial | Critical | Existing Chapa callbacks deployed; all deployed source not yet in repo; audit each and test forged/replayed callbacks |
| Daily reconciliation/receipts | Partial | Critical | Existing finance verification; no complete daily settlement evidence or five-language receipts |
| In-app/email/SMS notifications | Partial | Medium | Notifications/backend sessions exist; email delivery unverified; optional SMS not configured |
| Mela Next/mastery/future map | Partial | Medium | C LearnerTools; goal-type bug locally fixed/tested; step completion lifecycle remains |
| Parent linking/progress/consent | Partial | High | C ParentLearnerProgress; guardian SQL negative tests; safeguarding consent E2E pending |
| Teacher classroom/observations/reviews | Partial | High | C teacher components, A reviewer onboarding; qualification/subject binding exists; access recovery locally fixed |
| First super admin activation | Partial | Critical | A admin control-plane migrations; real bootstrap/MFA ceremony and configured-owner evidence pending |
| RBAC/MFA/session security | Partial | Critical | A admin-access.ts, registry migrations; negative tests exist; real MFA/session revocation journey pending |
| Admin users/employer/teacher verification | Partial | High | A OperationalModule/TeacherVerificationPanel; audited controls; operator acceptance pending |
| Admin commissions/settings | Partial | High | A InvitationCommissionControl; server config exists; commission policy/payment-linked changes need acceptance |
| Admin finance/disputes | Partial | Critical | Read-only finance and dispute inbox; settlement controls intentionally incomplete |
| Admin moderation/audit/security logs | Partial | High | A audited SQL updates, moderation and proctor queues; full coverage/access/retention verification pending |
| Admin content studio/versioning | Partial | High | Educator review queues exist; full author→translate→version→publish studio not found |
| Admin announcements/analytics | Partial | Medium | Overview counts/operational data; requested complete editorial/announcement lifecycle not certified |
| Admin Realtime/twelve-section layout | Partial | Medium | Module definitions and AI workforce exist; complete subscription/permission/layout acceptance pending |
| Five-language UI | Partial | High | Languages catalog exists; English strings widespread; full keyed translation/rendering review needed |
| Mobile/low-bandwidth/lazy bundles | Partial | Medium | Lazy routes and prior responsive tests; real low-end Android/slow-network acceptance pending |
| Installable/offline PWA | Missing | Medium | No consumer manifest/service worker found; design auth-safe caching before packaging |
| Accessibility | Partial | High | Labels/recovery improvements; human keyboard/screen-reader review pending |
| Minor-safe communication/video/reporting | Partial | Critical | Guardian/report/video schemas; video disabled; supervised contact and consent acceptance required |
| Terms/privacy/refund/mentor/employer/content policies | Partial | High | Privacy endpoints exist; complete local-lawyer-approved document suite not evidenced |
| K–12 content/translations | Partial | High | Live catalog: 126 school-subject programs; educator and translation gates pending; count is not quality |
| Higher education content | Partial | High | 5 TVET foundation, 4 TVET pathway, 8 university foundation, 6 university pathway programs; complete reviewed lessons not established |
| Unified AI agents | Partial | High | 26 agents enabled live; execution/approval layer exists; 26 registrations do not prove free cost, safe behavior or provider availability |
| Automated tests | Partial | High | 54 consumer and 49 admin tests last passed; SQL tests cover selected boundaries; missing full negative/E2E matrix |
| 5,000 concurrent users / scale path | Missing | Critical | No measured load-test evidence; run only in isolated staging with defined budget and success thresholds |
| Backups and tested restore | Missing | Critical | Live restore gate pending; migration drift makes this especially important |
| Monitoring/uptime/rollback | Partial | High | Pages smoke and operational health exist; alert delivery and restore/rollback exercise pending |
| Production Netlify/domain/SSL/staging | Partial | High | Pages CI exists; desired hosting/domain and isolated staging unverified |
| Play Store wrapper/listing | Missing | Medium | No signed package/store review evidence |
| Campus pilot/one-year expansion | Missing | High | No verified 50–100-student pilot outcomes/partner commitments; owner-led activity |

## Prioritized build order

1. Phase 2: version live-schema gaps; repair coin ledger and badge trigger; private RLS/indexes; review privileged functions and negative authorization tests. Preserve financial kill switches.
2. Phase 3: complete the 23-item admin acceptance matrix (bootstrap, RBAC, MFA, session, user lifecycle, identity, employer, mentor, teacher, audits, security logs, payments, disputes, commissions, content, moderation, announcements, analytics, realtime, frontend hosting, admin hosting, rollback, go/no-go). Do not label it certified from mocked tests.
3. Phase 4: approved telebirr sandbox then CBE Birr; webhook/refund/reconciliation/fraud/receipts tests. Block live money until proof.
4. Phases 5–9 in supplied order: end-to-end modules; translation/PWA/accessibility; child safety/legal; approved curriculum and editorial workflow; controlled AI routing.
5. Phase 10: full E2E, isolated capacity test, tested restore, error/uptime alerts. Fix defects before release.
6. Phase 11: desired hosting/domain/staging, store packaging, consented school pilot, issue remediation and launch materials. A one-year roadmap is ongoing execution, not something a single coding session can certify complete.

## Phase 1 summary

Done: inventory, critical mismatches, live advisor snapshot, readiness rubric, prioritized order. Tested: read-only schema checks and a rollback-only coin failure reproduction; prior frontend test results retained with scope. Remaining: Phase 2 onward; omitted deployed source and migration reconstruction are material risks.

OWNER_ACTION_REQUIRED: provider sandbox access/docs, Brevo sender/domain administration, supported password protection configuration, domain/hosting account control, named legal/safeguarding/editorial/translation reviewers, canonical 53-field program, campus pilot partner and consent. No passwords or payment keys should be pasted into chat. Dates for external approvals remain uncommitted; each is due before its dependent phase can be certified.
