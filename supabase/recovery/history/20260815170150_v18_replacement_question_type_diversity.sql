-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815170150
with r as (
  select t.target_question_id,p.subject_key,
         row_number() over(partition by t.program_key order by t.priority,t.target_question_id) rn
  from private.mela_question_replacement_targets_v18 t
  join public.mela_learning_programs p on p.program_key=t.program_key
), typed as (
  select target_question_id,
    case
      when subject_key in ('mathematics','physics','chemistry','economics','general_science','biology','agriculture','environmental_science','information_technology') then
        case ((rn-1)%20)+1
          when 1 then 'single_choice' when 2 then 'single_choice' when 3 then 'single_choice' when 4 then 'single_choice' when 5 then 'single_choice'
          when 6 then 'multi_select' when 7 then 'multi_select' when 8 then 'multi_select'
          when 9 then 'numeric' when 10 then 'numeric' when 11 then 'numeric'
          when 12 then 'scenario_choice' when 13 then 'scenario_choice' when 14 then 'scenario_choice'
          when 15 then 'short_answer' when 16 then 'short_answer'
          when 17 then 'true_false' when 18 then 'matching' when 19 then 'ordering' else 'passage_choice' end
      when subject_key in ('english','native_language','federal_working_language','foreign_language') then
        case ((rn-1)%20)+1
          when 1 then 'single_choice' when 2 then 'single_choice' when 3 then 'single_choice' when 4 then 'single_choice'
          when 5 then 'passage_choice' when 6 then 'passage_choice' when 7 then 'passage_choice' when 8 then 'passage_choice'
          when 9 then 'short_answer' when 10 then 'short_answer' when 11 then 'short_answer'
          when 12 then 'scenario_choice' when 13 then 'scenario_choice' when 14 then 'scenario_choice'
          when 15 then 'multi_select' when 16 then 'multi_select'
          when 17 then 'ordering' when 18 then 'ordering' when 19 then 'matching' else 'true_false' end
      when subject_key in ('history','civics','social_science','geography','moral_education') then
        case ((rn-1)%20)+1
          when 1 then 'single_choice' when 2 then 'single_choice' when 3 then 'single_choice' when 4 then 'single_choice'
          when 5 then 'passage_choice' when 6 then 'passage_choice' when 7 then 'passage_choice'
          when 8 then 'scenario_choice' when 9 then 'scenario_choice' when 10 then 'scenario_choice'
          when 11 then 'multi_select' when 12 then 'multi_select' when 13 then 'multi_select'
          when 14 then 'short_answer' when 15 then 'short_answer'
          when 16 then 'matching' when 17 then 'matching' when 18 then 'ordering' when 19 then 'true_false' else 'single_choice' end
      else
        case ((rn-1)%20)+1
          when 1 then 'single_choice' when 2 then 'single_choice' when 3 then 'single_choice' when 4 then 'single_choice'
          when 5 then 'scenario_choice' when 6 then 'scenario_choice' when 7 then 'scenario_choice' when 8 then 'scenario_choice'
          when 9 then 'matching' when 10 then 'matching' when 11 then 'matching'
          when 12 then 'ordering' when 13 then 'ordering' when 14 then 'ordering'
          when 15 then 'multi_select' when 16 then 'multi_select'
          when 17 then 'short_answer' when 18 then 'short_answer' when 19 then 'true_false' else 'passage_choice' end
    end desired_type
  from r
)
update private.mela_question_replacement_targets_v18 t
set desired_question_type=typed.desired_type,updated_at=now()
from typed where typed.target_question_id=t.target_question_id;
;
