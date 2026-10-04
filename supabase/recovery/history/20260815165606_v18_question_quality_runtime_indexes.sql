-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815165606
create index if not exists mela_question_bank_validation_program_number_idx on public.mela_question_bank(validation_status,program_key,question_number) where active;
create index if not exists mela_question_bank_topic_validation_tier_idx on public.mela_question_bank(topic_id,validation_status,access_tier,difficulty,question_number) where active;
create index if not exists mela_question_bank_chapter_validation_tier_idx on public.mela_question_bank(chapter_id,validation_status,access_tier,difficulty,question_number) where active;
;
