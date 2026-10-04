-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260822000616
revoke insert, update, delete on public.coin_transactions from authenticated; revoke all on public.coin_transactions from anon;
;
