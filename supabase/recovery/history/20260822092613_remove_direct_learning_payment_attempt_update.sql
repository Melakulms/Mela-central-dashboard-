-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260822092613
drop policy if exists "mela_payment_attempts_owner_update" on public.mela_learning_payment_attempts; revoke update on public.mela_learning_payment_attempts from authenticated;
;
