-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815171758
create index if not exists mela_qreplacement_program_idx on private.mela_question_replacement_targets_v18(program_key);
create index if not exists mela_qreplacement_chapter_idx on private.mela_question_replacement_targets_v18(chapter_id);
create index if not exists mela_qreplacement_topic_idx on private.mela_question_replacement_targets_v18(topic_id);
create index if not exists mela_qreplacement_status_priority_idx on private.mela_question_replacement_targets_v18(status,priority,program_key);
create index if not exists mela_qreview_decision_question_idx on private.mela_question_review_decisions_v18(question_id);
create index if not exists mela_qreview_decision_reviewer_idx on private.mela_question_review_decisions_v18(reviewer_id);
create index if not exists mela_qgeneration_status_program_idx on private.mela_question_generation_candidates_v18(status,program_key,generated_at);
create index if not exists mela_qreview_slices_status_program_idx on private.mela_question_review_slices_v18(status,program_key,slice_number);
;
