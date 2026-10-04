-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815093842
create index if not exists mela_question_bank_program_tier_number_idx
on public.mela_question_bank(program_key,access_tier,question_number)
where active;
;
