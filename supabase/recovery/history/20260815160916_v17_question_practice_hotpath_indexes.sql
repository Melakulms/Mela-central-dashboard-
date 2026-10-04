-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815160916
create index if not exists mela_question_bank_topic_tier_diff_number_idx on public.mela_question_bank(topic_id, access_tier, difficulty, question_number) where active;
create index if not exists mela_question_bank_chapter_tier_diff_number_idx on public.mela_question_bank(chapter_id, access_tier, difficulty, question_number) where active;
;
