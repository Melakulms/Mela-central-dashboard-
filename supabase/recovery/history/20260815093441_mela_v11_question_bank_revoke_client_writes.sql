-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815093441
revoke all on public.mela_question_sessions from authenticated;
grant select on public.mela_question_sessions to authenticated;
revoke all on public.mela_question_user_program_stats from authenticated;
grant select on public.mela_question_user_program_stats to authenticated;
revoke all on public.mela_question_bank from authenticated;
revoke all on public.mela_question_review_batches from authenticated;
;
