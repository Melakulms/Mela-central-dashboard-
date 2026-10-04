-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815093544
drop policy if exists mela_question_bank_client_deny on public.mela_question_bank;
create policy mela_question_bank_client_deny on public.mela_question_bank
for all to anon,authenticated using (false) with check (false);

drop policy if exists mela_question_review_batches_client_deny on public.mela_question_review_batches;
create policy mela_question_review_batches_client_deny on public.mela_question_review_batches
for all to anon,authenticated using (false) with check (false);
;
