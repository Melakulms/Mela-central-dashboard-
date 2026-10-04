-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260823064308
create index if not exists payments_admin_status_idx on public.payments(status, created_at desc);
create index if not exists learning_payment_attempts_admin_status_idx on public.mela_learning_payment_attempts(status, created_at desc);
create index if not exists escrow_payment_attempts_admin_status_idx on public.escrow_payment_attempts(status, created_at desc);
create index if not exists payout_requests_admin_status_idx on public.payout_requests(status, created_at desc);
create index if not exists earnings_ledger_admin_status_idx on public.earnings_ledger(status, created_at desc);
create index if not exists coin_transactions_admin_created_idx on public.coin_transactions(created_at desc);
;
