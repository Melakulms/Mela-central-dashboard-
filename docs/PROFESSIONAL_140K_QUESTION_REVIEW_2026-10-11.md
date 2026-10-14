# MELA — professional teacher review of the reported 140,000 questions
Operational protocol, 11 October 2026

**Current status:** infrastructure and proposed security changes only. No claim that
140,000 questions have been read or approved by human teachers. The exact live
active-question count is not yet independently verified, because the Supabase
connection available to this agent is INACTIVE and does not match the live
student frontend Supabase URL.

## Professional authorization
1. A real teacher signs up under the **Teacher** role; a verified identity and
   account are required.
2. An authorized Central Admin officer opens Moderation → Teacher reviewer
   verification, checks qualification, school/TVET/university affiliation,
   teaching subjects and eligible grade levels. Evidence stays in the
   appropriately protected account/admin record; never upload private IDs into
   public GitHub.
3. Only an approved teacher with active subject authorization may access an
   applicable grade and subject's review work. Admins manage verification
   and monitor audit records, but cannot supply a teacher's decision.
4. Revoke approval immediately when credentials are withdrawn or questioned.

## Question-by-question professional rubric
Each teacher must independently attempt each question **before** consulting
the stored answer and then assess:
- grade and subject alignment to Ethiopian curriculum and source edition;
- factual accuracy, mathematical correctness, unambiguous wording;
- answer key, accepted variants/tolerance, explanation and grading fairness;
- plausible, non-misleading distractors for multiple-choice questions;
- language quality across intended local languages, accessibility,
  discrimination or harmful stereotypes, student safety and source rights;
- duplicate/near-duplicate items and unintended answer leakage.

Record **Approve** only after the manual attempt and a specific verification
note. Otherwise choose **Changes required** with the exact correction, not
a generic rejection. Machine confidence is only a triage hint.

## Throughput and coverage
1. Confirm exact question totals and exact review-slice coverage with
   `supabase/maintenance/140k_review_queue_reconciliation_manual.sql`,
   dry-run only at first. 140,000 questions equate to approximately 1,400
   100-question slices, if all are distinct, active and batched in that format.
2. Reconcile the missing active-question IDs into new **pending** review slices
   only after staging dry-run, approval and a backup. Never mark those as approved.
3. Use the paginated, grade-and-subject-limited review queue; verified teachers
   claim one slice atomically. Two teachers cannot overwrite each other's
   claimed reviews or read that colleague's answer keys.
4. Save partial individual decisions and return to the same slice. An approved
   slice requires decisions for every item; corrected content needs another
   professional review. Maintain visible Pending / Assigned / In review /
   Changes required / Approved counts.
5. Quality assurance: assign a second independent teacher for a documented
   risk-based sample and escalations, including any grading-key corrections.
   Critical high-stakes questions may warrant dual-review policies before release.
6. Use the provided progress RPC to display question counts **within each
   teacher's authorized subjects**. Admin-global totals require a separate,
   authenticated, MFA-protected oversight endpoint and verified production DB.
7. A version-controlled publication gate must eventually ensure students do
   not receive unreviewed questions. The existing `deterministic_validated`
   quality state is **not** proof of human teacher approval. Do not falsely
   describe all published questions as professionally verified.

## Example acceptance criteria
- Teacher A (approved Mathematics, Grade 4) sees and claims only corresponding
  Mathematics Grade 4 review slices.
- Teacher B cannot claim A's slice, access answer keys or submit decisions as A.
- Administrator can approve real teacher profiles, but cannot claim slices,
  inspect grading data or save a professional question decision.
- All approval decisions include the actual signed-in teacher, own test
  response, note, timestamp and affected item.
- Revoked teachers and anonymous users cannot read or submit review work.
- Unreviewed or unassigned questions never get an artificial teacher-approved
  status.
- Inventory dry-run produces **zero missing active questions** when the
  reconciliation is complete. A zero queue is never assumed to mean approval.
- No live release until staging security tests, subject-grade validations and
  actual partner-teacher UAT pass.

## Connect and deploy safely
The current connected Supabase project is `rztqmkklqsspchenjijh`, named
`supabase-bronze-chair`, status INACTIVE. The MELA deployment repository
uses a different project. **Never apply these migrations to the inactive,
mislinked project.**

After the actual MELA Supabase project is connected and reviewed:
1. inspect migrations/dependencies for compatibility;
2. take protected schema backup and stage the changes;
3. apply `20261011133500_professional_question_review_paging.sql` in staging;
4. run `supabase/tests/professional_teacher_review_v39.sql` and actual
   role-based staged test accounts (not just static assertions);
5. review dry-run counts and perform controlled reconciliation if needed;
6. ship a compatible teacher frontend, verify on phone, then release
   production only after sign-off.

**Not performed:** hiring teachers, obtaining qualification evidence,
correcting 140,000 question answers, running against the real database,
certifying any question or deploying the staging migration.
