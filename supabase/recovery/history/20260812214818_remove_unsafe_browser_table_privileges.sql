-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812214818
-- RLS does not protect TRUNCATE. Browser roles never need schema-level TRUNCATE/TRIGGER/REFERENCES rights.
revoke truncate, references, trigger on all tables in schema public from anon, authenticated;
alter default privileges for role postgres in schema public revoke truncate, references, trigger on tables from anon, authenticated;

-- Also protect new operational tables explicitly.
revoke truncate, references, trigger on public.escrow_payment_attempts,public.payout_accounts,public.payout_requests,public.proctor_reviews,public.career_coach_usage from anon,authenticated;

;
