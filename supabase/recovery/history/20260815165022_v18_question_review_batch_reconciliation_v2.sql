-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815165022
update public.mela_question_review_batches b
set deterministic_validated_count=x.mastery_count,
    review_status='changes_required',
    notes=concat_ws(E'\n',nullif(b.notes,''),'v18 quality audit: only subject-mastery candidates count toward premium/mastery certification. Curriculum-navigation and generic-study questions are now review_required; regeneration queue targets at least 500 mastery-quality questions per program before educator approval.'),
    updated_at=now()
from (
 select q.program_key,count(*) filter(where a.purpose_class='subject_mastery_candidate')::int mastery_count
 from public.mela_question_bank q
 join private.mela_question_quality_audit_v18 a on a.question_id=q.id
 where q.active
 group by q.program_key
) x
where x.program_key=b.program_key;
;
