-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815164505
update public.mela_question_bank q
set quality_checks = coalesce(q.quality_checks,'{}'::jsonb) || jsonb_build_object(
      'v18_purpose_class',a.purpose_class,
      'v18_requires_regeneration',a.requires_regeneration,
      'v18_audited_at',a.audited_at),
    machine_quality_score = case
      when a.purpose_class='curriculum_navigation' then least(q.machine_quality_score,65)
      when a.purpose_class='generic_study_skill' then least(q.machine_quality_score,55)
      else q.machine_quality_score end,
    validation_status = case when a.requires_regeneration then 'review_required' else q.validation_status end,
    updated_at=now()
from private.mela_question_quality_audit_v18 a
where a.question_id=q.id;
;
