# MELA readiness review — 10 October 2026

Decision: retain the invite-only controlled beta. Unrestricted public launch is not yet verified.

## Repair delivered
The mentor screen offered replacement scheduling after cancellation, but the database rejected the cancelled → scheduled transition. After permitting that transition, a repeated scheduling notification hit the notification deduplication constraint and aborted the whole operation. Both failures were reproduced using ordinary authenticated roles in rollback-only database tests.

Migration `20261010034002_repair_cancelled_mentorship_rescheduling.sql` is applied live. A mentor can restore a cancelled appointment to a future time, clearing cancellation state. Scheduling notifications include the appointment time/duration and exact retries do not duplicate them. Completed appointments explicitly refuse rescheduling, preserving their completion and rating history. Request-row locking and the existing participant authorization remain.

## Evidence collected today
- Learner: 119 tests in 26 suites; production build passes.
- Admin/API: 261 tests in 20 suites; production build passes.
- Live smoke scripts pass for both published apps, Auth health, Data API, invite-only beta authentication, fail-closed email confirmation settings, and unauthenticated admin endpoint denial. Health/settings checks do not prove email delivery.
- Seven live rollback regression files pass: mentorship rescheduling, mentorship ratings, course catalog/enrollment/completion/retries, classroom access, guardian progress, assessment integrity, and private-table boundaries. Fixtures were rolled back.
- Public/admin tables without RLS: zero.
- Security advisor counts unchanged: 15 no-policy informational notices, 90 authenticated privileged-wrapper notices, one intentional anonymous certificate-verification wrapper, and one disabled leaked-password-protection warning. This is not a complete audit of every privileged function.
- Performance advisor: unused-index information only; no missing foreign-key index warning.
- Frontend source did not change in this repair; database behavior is live immediately.

## Remaining launch gates
| Gate | Current evidence | Needed before unrestricted launch |
| --- | --- | --- |
| Course content | 53 courses, 22 lessons in two courses; 51 courses lack lesson content | Complete course curricula, exercises, rights review and acceptance |
| Curriculum coverage | 149 active programs, 887 chapters; 23 empty programs | Fill actual coverage gaps |
| Educational review | 142,396 active questions; zero educator-verified questions, zero source-verified chapters, zero approved chapter reviews | Qualified subject/grade reviews and documented source rights; deterministic validation is not educator approval |
| Account operations | Public health and invite-only onboarding endpoint checks pass | Real production signup/recovery, role-by-role signed-in browser acceptance, administrator MFA and recovery |
| Operational recovery | No restore or capacity rehearsal evidence in this review | Backup restoration rehearsal, capacity results, monitored incident response ownership |
| Language and safeguarding | Interface localization exists; not all learning content is translated | Native-language acceptance and legal/safeguarding sign-off |
| Deferred modules | Payments, payouts, paid work, challenges and video calls disabled | Remain deferred; no financial or video readiness claim |

Live beta configuration confirms `public_launch=false` and `requires_email=false`. No unrestricted launch flag was enabled. Neither passing automated tests nor published pages establish that all real-world user journeys are certified.

Existing dated release reports remain historical records. This review adds current evidence without marking unresolved gates as passed.
