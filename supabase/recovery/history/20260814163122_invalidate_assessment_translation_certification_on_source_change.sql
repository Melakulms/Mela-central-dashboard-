-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260814163122
create or replace function private.invalidate_assessment_language_certification_from_source_change()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare v_assessment uuid; begin
  v_assessment:=coalesce(new.assessment_id,old.assessment_id);
  if coalesce(new.language_code,old.language_code)<>'en' then return coalesce(new,old); end if;

  update public.assessment_question_translations t
     set status='draft',updated_at=now()
   where t.assessment_id=v_assessment;

  update public.assessment_language_review_assignments
     set status=case when status='approved' then 'in_review' else status end,
         reviewer_notes=case when status='approved' then 'English source assessment changed; fresh review required.' else reviewer_notes end,
         submitted_at=case when status='approved' then null else submitted_at end,
         updated_at=now()
   where assessment_id=v_assessment and language_code in ('am','om','ti','so') and status<>'cancelled';

  update public.assessment_language_certifications
     set status='in_review',certified_at=null,reviewed_by=null,
         reviewer_notes='English source assessment changed; translated credential version requires fresh review.',
         certification_metadata='{}'::jsonb,updated_at=now()
   where assessment_id=v_assessment and language_code in ('am','om','ti','so');
  return coalesce(new,old);
end $$;

drop trigger if exists trg_invalidate_assessment_language_on_question_update on public.assessment_questions;
create trigger trg_invalidate_assessment_language_on_question_update
after update of prompt,choices,competency,version,active on public.assessment_questions
for each row
when (old.prompt is distinct from new.prompt or old.choices is distinct from new.choices or old.competency is distinct from new.competency or old.version is distinct from new.version or old.active is distinct from new.active)
execute function private.invalidate_assessment_language_certification_from_source_change();

drop trigger if exists trg_invalidate_assessment_language_on_question_insert on public.assessment_questions;
create trigger trg_invalidate_assessment_language_on_question_insert
after insert on public.assessment_questions
for each row when (new.language_code='en')
execute function private.invalidate_assessment_language_certification_from_source_change();

drop trigger if exists trg_invalidate_assessment_language_on_question_delete on public.assessment_questions;
create trigger trg_invalidate_assessment_language_on_question_delete
after delete on public.assessment_questions
for each row when (old.language_code='en')
execute function private.invalidate_assessment_language_certification_from_source_change();

revoke execute on function private.invalidate_assessment_language_certification_from_source_change() from public,anon,authenticated;
grant execute on function private.invalidate_assessment_language_certification_from_source_change() to service_role;

;
