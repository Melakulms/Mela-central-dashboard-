# MELA platform diagnostic and controlled-beta acceptance — 14 October 2026

> Scope: source-code inspection of both live-linked GitHub repositories, GitHub Actions, Vercel deployment metadata, and prior dated engineering evidence. **Not** a current credentialed penetration test, educational certification, or live Supabase production audit. This report separates a completed code fix from a deployed/verified production fix.

## Overall verdict

**NO-GO for unrestricted public launch, earnings/payments, or cash-prize competitions.** Controlled beta with **unique, one-use role-matching invites** can proceed only with disposable/non-sensitive profiles, explicit participant instructions and human oversight. Until current production RLS and live account isolation are checked, avoid real minors' identifiers, teacher identity scans, financial details, sensitive messages or other unnecessary personal data.

## Deployment and source of truth

- Learner source: `Melakulms/mela-app` on `main`; student-facing Pages URL `https://melakulms.github.io/mela-app/`. Latest observed main commit before report: `4e4c7765`. GitHub Pages deployment, unit tests, and Android Chromium mobile smoke at that commit were reported successful on 14 October.
- Central Admin source: `Melakulms/Mela-central-dashboard-` on `main`; legacy Pages URL `https://melakulms.github.io/Mela-central-dashboard-/`. Vercel production project `central-dashboard`, alias `central-dashboard-gamma.vercel.app` (separate origin), is linked to this repository. Vercel readiness status by itself does not demonstrate authenticated access or functional Android PWA installation.
- Actual production Supabase ref in repositories: `duizgtmbptmlbyipreqg`. Available connected Supabase account currently only lists inactive `rztqmkklqsspchenjijh`. **No fresh live production SQL/advisor/Auth-setting checks or production Edge Function deployments were possible through this Supabase connection.**
- Admin source PR #51 merged: `vercel.json` now routes expected admin PWA path on Vercel and specifies server-delivered anti-framing/CSP headers. Runtime verification on production remains separate. Admin PR #50 merged: unconditional AAL2+active-account guards in `mela-content-admin` source; **production Edge Function requires explicit deployment**.
- The small isolated user/admin Vitest suites and GitHub Actions passing are useful smoke/contract evidence, not proof of live permission enforcement. Never use production owner credentials for bulk test fixtures.

## Diagnosis by launch area

| Area | Evidence of implementation | Outstanding defect, limitation, or acceptance |
|---|---|---|
| Registration & login | Separate student, parent, teacher and company forms; invite codes are role-matched and consumed atomically; email auth integrated. | User-reported SMTP confirmation failures and expired confirmation redirect. Verify real sign-up, confirmation, reset, logout, and session restoration using disposable users. Keep closed-beta invite path available; stop signups if suspicious bot activity increases. |
| Account roles | Role-specific profile save RPCs and independent student/teacher/company/family views. | Fresh production proof required that a self-selected role, mutable user_metadata, or stale JWT cannot grant teacher, employer, reviewer, or admin permission. |
| Profiles & education levels | Grade/stage and subject-save confirmation routines, explicit incomplete onboarding. | Real-device writes, RLS, completion progress, parental/teacher/company flows and error recovery unverified. Student profile/subjects must not leak across users. |
| Navigation, Settings & Android | URL-based learner routes, session-state cleanup, mobile Chromium automated smoke. | Recurring owner reports of stuck Settings, stale installed PWA, and Back/Home navigation. Repeat with real installed Android app under fresh and existing sessions; compare in-app release hash. |
| Central Admin | Server-side admin registry and permission checks, AAL2 in main API, private/in-memory session, separate install manifest. | Admin Authenticator recovery, real Google Authenticator codes, suspended account revocation and domain isolation not yet authenticated tested. Existing Pages admin domain shares learner origin; retire it after separate Vercel origin validated. |
| Database / API | Oct 13 evidence of RLS on 265 public tables, seven private buckets, three security-invoker views. | Counts are **dated evidence**, not current measurement. Inventory callable privileged RPCs, Storage policies, grants, account isolation and auth-stale semantics against the **actual** production project. |
| Question bank (~142k) | Deterministic validation, topic/grade mappings and teacher-review interfaces. | Large unreviewed professional-human review backlog. Teacher qualification, subject+grade assignment, blind review, appeals, answer-key access and live queue assignment require acceptance. Historical answer-key seed SQL is publicly accessible; treat those questions as compromised for cash/prize use. |
| AI courses (53) | Catalog, introductory workbook drafts, resources, project briefs and self-check assets. | Editorial/qualified review, translations, real learner timing validation and professional certification incomplete. Existing source descriptions distinguish course packs from 51 earlier lesson-empty published catalog entries; do not claim all were deployed as complete accredited programs. |
| AI tutor / agent endpoints | User-authenticated gateway with server-side reservation and daily spend bounds, child-safety system instructions. | Check actual provider key/config and token spending; protect suspended/deleted accounts in coordinator, review request logging for sensitive data, verify budget in live project. |
| Practice/assessments | Server grading, retry-safe submission, timed assessment code. | Authenticated test of resume, grade-scoped access, hidden correct answers, multi-device cheating, proctoring consent and certificate issuance needed. |
| Arena & competitions | Matchmaking, readiness, eight rounds and scoring validated in isolated regressions. | Eight named competition experiences and two-real-player timing/rating settlement not certified; do not enable monetary rewards before anti-cheat, abuse response, and real finance compliance. |
| Opportunity Hub & scholarships | Opportunity search, applications, eligibility UX and official-resource link handling exist. | Verify actual live 2,000-source inventory, dead links, license/attribution, eligibility, company posting authorization, and real submission history. External site applications cannot be tracked as completed without confirmation. |
| Teacher & parent safeguards | Private qualification upload bucket, reviewer approvals, guardian consent flows. | Verify scanned PDF/JPG security, signed-link expiry, administrator evidence access and child consent. Avoid real sensitive uploads while beta isolation unproven. |
| Mentorship/marketplace | Booking/request and contract/dispute workflows exist. | Real scheduling, role verification, safety moderation, award/contract state, and dispute settlement tests remain. |
| Payments, escrow & wallet | Service-only payment settlement and anti-replay code previously reviewed. | Deliberately deferred; financial and prize pathways must remain disabled until provider sandbox and legal controls tested. |
| Languages | Shell and core controls for five supported languages. | Deep lessons/questions and role-specific flows not fully professionally localized; do not mark content approved from UI translations. |
| Data protection/IP | No known client service-role key in source as of dated Oct 13 review; public GitHub repositories. | Public source can be copied. Restrict sensitive material, licensing and repository access appropriately; remove public answer keys from current files and history where legally/operationally safe, and rotate compromised questions. No technical control eliminates copying of visibly delivered pages. |
| Operations | GitHub CI/Pages and Vercel production deployment metadata available; patch drafts/merges traceable. | Confirm Vercel headers/assets and PWA via live smoke; verify production alerting, backup restore, attack/abuse monitoring, incident response, account deletion and staged rollback. |

## Immediate acceptance tests before broadening access

1. Verify deployed learner and isolated admin PWA hashes, real HTML/JS/manifest/SW status and CSP headers with `.github/workflows/production-security-smoke.yml`.
2. Provision dedicated test profiles (student A, student B, parent, approved/unapproved teacher, company, approved admin). Verify outsider reads/updates and privileged RPCs fail on every route, including cross-account IDs.
3. Register through both valid email and one-use invitation; follow mail link on Android, check expiry, restore session, password reset and invite replay rejection. Repair SMTP/redirect allowlist on production Auth; this requires production admin access.
4. Exercise account-status transitions and revoked sessions; MFA TOTP enrollment, backup factor and lost-factor recovery; no password-only admin bypass.
5. Finish proper end-to-end role navigation, question teacher review, grade/subject segregation, challenge scoring, mentor booking and company opportunities; ensure test data is disposable and cleanup is audited.
6. Enable monitored abuse limits, review current production Supabase security and advisors; keep payments, paid-work, payouts, video and cash prizes deferred. Rehearse restoration before wider launch.

## Stop / rollback triggers

Pause invitations immediately for evidence of unauthorized data disclosure, teacher/company/admin privilege promotion, inconsistent role assignment, compromised credentials, unexplained wallet increments, impersonation, child-safety incidents, or material production API abuse. Do not announce success based only on a 200 response, passing JS unit tests or Vercel READY.

## Next authorized delivery dependency

Production Supabase connection must grant scoped access to **`duizgtmbptmlbyipreqg`** to verify RLS, inspect Auth settings, and deploy corrected content/AI Edge Functions. No password or service key needs to be pasted into chat. Until that happens, the production backend remains outside this audit's live-verification scope.
