-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815164648
truncate private.mela_question_regeneration_queue_v18;
insert into private.mela_question_regeneration_queue_v18(program_key,grade_level,subject_title,track_key,current_mastery_count,target_mastery_count,questions_needed,priority,generation_policy)
select p.program_key,p.grade_level,p.subject_title,p.track_key,
       count(*) filter(where a.purpose_class='subject_mastery_candidate')::int,
       500,
       greatest(500-count(*) filter(where a.purpose_class='subject_mastery_candidate'),0)::int,
       case when p.grade_level in (12,1,2,3) then 10 when p.grade_level in (4,5,6,11) then 20 else 30 end,
       jsonb_build_object('required_question_types',jsonb_build_array('single_choice','true_false','multi_select','numeric_or_short_answer','scenario_or_passage'),'require_subject_content',true,'exclude_curriculum_navigation',true,'answer_must_be_machine_gradable',true,'educator_review_required',true,'paid_majority_target',true)
from public.mela_learning_programs p
join public.mela_question_bank q on q.program_key=p.program_key and q.active
join private.mela_question_quality_audit_v18 a on a.question_id=q.id
where p.program_kind='school_subject' and p.grade_level between 1 and 12
group by p.program_key,p.grade_level,p.subject_title,p.track_key;
;
