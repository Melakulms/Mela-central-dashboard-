-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260814163554
create policy assessment_language_reviewer_qualifications_read_own_or_admin
on public.assessment_language_reviewer_qualifications
for select to authenticated
using (reviewer_id=(select auth.uid()) or private.is_admin_user());

create policy assessment_question_translations_read_assigned_or_admin
on public.assessment_question_translations
for select to authenticated
using (
  private.is_admin_user()
  or exists(
    select 1 from public.assessment_language_review_assignments a
    where a.assessment_id=assessment_question_translations.assessment_id
      and a.language_code=assessment_question_translations.language_code
      and a.reviewer_id=(select auth.uid())
      and a.status<>'cancelled'
  )
);

;
