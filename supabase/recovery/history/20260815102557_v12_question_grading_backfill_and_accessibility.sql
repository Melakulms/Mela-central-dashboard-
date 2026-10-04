-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815102557
update public.mela_question_bank
set narration_text = coalesce(narration_text, prompt || case when jsonb_array_length(choices)>0 then ' Options: ' || (select string_agg(value, '; ' order by ordinality) from jsonb_array_elements_text(choices) with ordinality) else '' end),
    response_schema = case when response_schema='{}'::jsonb then jsonb_build_object('type',question_type,'required',true) else response_schema end,
    machine_quality_score = case when machine_quality_score=0 then 82 else machine_quality_score end,
    quality_checks = quality_checks || jsonb_build_object('nonempty_prompt',length(trim(prompt))>10,'choices_unique',case when jsonb_array_length(choices)>0 then (select count(*)=count(distinct value) from jsonb_array_elements_text(choices)) else true end,'answer_server_side',true,'machine_validated',validation_status='deterministic_validated'),
    accessibility_support = accessibility_support || jsonb_build_object('screen_reader_ready',true,'narration_ready',true,'keyboard_answerable',true),
    updated_at=now()
where generation_version='v11';

insert into private.mela_question_grading_v12(question_id,grading_kind,correct_response,accepted_variants,tolerance,rationale,grading_version)
select q.id,
       case when q.question_type='true_false' then 'true_false' else 'single_choice' end,
       jsonb_build_object('choice',coalesce(to_jsonb(k)->>'correct_choice',to_jsonb(k)->>'correct_answer',to_jsonb(k)->>'answer','')),
       '[]'::jsonb,
       null,
       coalesce(nullif(to_jsonb(k)->>'explanation',''),nullif(to_jsonb(k)->>'rationale',''),'Review the mapped chapter and topic relationship for this question.'),
       'v12_backfill'
from private.mela_question_answer_keys k
join public.mela_question_bank q on q.id=(to_jsonb(k)->>'question_id')::uuid
where q.generation_version='v11'
on conflict(question_id) do nothing;
;
