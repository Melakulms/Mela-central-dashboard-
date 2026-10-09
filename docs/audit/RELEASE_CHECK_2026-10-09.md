# MELA release check — 9 October 2026

The platforms remain deployed for the controlled beta. This checkpoint is engineering delivery, not unrestricted-launch or educational certification.

## Delivered

- Curriculum questions: 142,396 retained; 16,510 topic/chapter links repaired; zero remaining link mismatches. Composite constraints and covering indexes prevent future classification drift. Learner grade/stage enforcement applies to modern and legacy session endpoints.
- Question practice: subject, academic-track, chapter, topic and difficulty filters; choice IDs and numeric responses match the typed grader; retries do not duplicate results.
- Skill Academy: metadata reports actual lesson/preview counts without revealing restricted lesson text. Courses without lessons cannot be newly enrolled through either the client insert or enrollment RPC. Free enrollment is retry-safe and retains saved progress. Paid enrollment remains deferred.
- Lesson reader: safe headings, lists and code blocks, preview mode without completion writes, unfinished-lesson restoration, previous/next navigation and saved completion feedback.
- Public entry screens: language selection before sign-in; sign-in, beta registration, beta recovery, email verification and password reset interface messages in English, Amharic, Afaan Oromo, Tigrinya and Somali. Language changes preserve entered form values. Recovery-code clipboard failures are visible.
- Content Studio: complete paginated course, curriculum-program, chapter-review and question-review inventories; grade/subject filters; lesson inspection; course-linked material draft preparation with ordinary authoring fields and rejection of incomplete review submissions; draft status filters and pagination. Existing MFA and content-permission requirements remain. Saving/submitting a draft does not publish or approve it.

## Verification

- Learner: 119 tests across 26 suites; production build passes.
- Admin/API: 261 tests across 20 suites; production build passes.
- Rollback-only course regression uses ordinary authenticated/anonymous roles: private inventory denial, unpublished metadata exclusion, preview/full access, duplicate enrollment, partial progress retained after enrollment retry, full completion and exactly one certificate, empty/paid/unpublished enrollment refusal. Fixtures rolled back.
- Database migration `academy_catalog_and_enrollment_readiness` applied as version 20261009183520. Content Edge Function deployed as version 3 with JWT verification.
- Advisors: no new security warnings and no missing foreign-key indexes. Existing intentional privileged-wrapper notices and plan-limited password-protection notice remain.

## Actual content supply and remaining release dependencies

The course catalog has 53 records. Two free courses contain 22 lessons; the other 51 are paid courses without lesson text. They remain visible as courses in preparation, with enrollment unavailable. They are not completed courses or a certified 53-field curriculum.

The database also holds 160 career-path lessons across eight different paths. Sample content is generic/template material; it is not a substitute for the 51 AI course curricula and was not relabeled or copied into them.

77,044 question records are deterministically validated/mastery candidates; 65,352 await review. Educator verification, curriculum/source-rights review, native-language acceptance, and legal/safeguarding sign-off still require real qualified reviewers and evidence. Translated interface strings do not translate lesson or question content.

Authenticated production-browser acceptance, external email delivery/recovery, administrator MFA recovery, restore rehearsal and capacity evidence remain open. Existing invite/recovery-code onboarding avoids email dependency for the controlled beta. Payments, payouts, paid work, video calls and other deferred features remain disabled as previously directed.

Do not change these dependencies to passing or enable unrestricted public launch without the corresponding evidence.
