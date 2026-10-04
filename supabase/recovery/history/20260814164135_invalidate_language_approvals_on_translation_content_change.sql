-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260814164135
create or replace function private.invalidate_assessment_language_approvals_on_translation_change()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if tg_op='UPDATE' and not (
    old.prompt is distinct from new.prompt
    or old.choices is distinct from new.choices
    or old.competency is distinct from new.competency
    or old.source_version is distinct from new.source_version
    or old.translation_version is distinct from new.translation_version
  ) then return new; end if;

  update public.assessment_language_review_assignments
     set status=case when status='approved' then 'in_review' else status end,
         reviewer_notes=case when status='approved' then 'Translated assessment content changed after approval; fresh review required.' else reviewer_notes end,
         submitted_at=case when status='approved' then null else submitted_at end,
         updated_at=now()
   where assessment_id=new.assessment_id and language_code=new.language_code and status<>'cancelled';

  update public.assessment_language_certifications
     set status='in_review',certified_at=null,reviewed_by=null,
         reviewer_notes='Translated assessment content changed; fresh independent reviews are required.',
         certification_metadata='{}'::jsonb,updated_at=now()
   where assessment_id=new.assessment_id and language_code=new.language_code and status<>'draft';
  return new;
end $$;

drop trigger if exists trg_invalidate_language_approvals_on_translation_change on public.assessment_question_translations;
create trigger trg_invalidate_language_approvals_on_translation_change
after insert or update of prompt,choices,competency,source_version,translation_version on public.assessment_question_translations
for each row execute function private.invalidate_assessment_language_approvals_on_translation_change();

revoke execute on function private.invalidate_assessment_language_approvals_on_translation_change() from public,anon,authenticated;
grant execute on function private.invalidate_assessment_language_approvals_on_translation_change() to service_role;
;
