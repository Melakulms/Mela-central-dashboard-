-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815164404
truncate private.mela_question_quality_audit_v18;
insert into private.mela_question_quality_audit_v18(question_id,program_key,purpose_class,requires_regeneration,audit_flags)
select q.id,q.program_key,
 case
  when q.prompt ilike '%how to study%' or q.prompt ilike '%study item%' or q.prompt ilike '%chapter has 3 mapped learning topics%' then 'generic_study_skill'
  when q.prompt ilike '%which chapter%' or q.prompt ilike '%mapped topic%' or q.prompt ilike '%put these three chapter labels%' or q.prompt ilike '%chapter should the learner open%' then 'curriculum_navigation'
  else 'subject_mastery_candidate' end,
 case when q.prompt ilike '%how to study%' or q.prompt ilike '%study item%' or q.prompt ilike '%chapter has 3 mapped learning topics%' or q.prompt ilike '%which chapter%' or q.prompt ilike '%mapped topic%' or q.prompt ilike '%put these three chapter labels%' or q.prompt ilike '%chapter should the learner open%' then true else false end,
 jsonb_build_object('audit_version','v18','reason',case
  when q.prompt ilike '%how to study%' or q.prompt ilike '%study item%' or q.prompt ilike '%chapter has 3 mapped learning topics%' then 'generic/meta-learning prompt'
  when q.prompt ilike '%which chapter%' or q.prompt ilike '%mapped topic%' or q.prompt ilike '%put these three chapter labels%' or q.prompt ilike '%chapter should the learner open%' then 'curriculum-navigation prompt rather than subject mastery'
  else 'no v18 meta-navigation pattern detected' end)
from public.mela_question_bank q where q.active;
;
