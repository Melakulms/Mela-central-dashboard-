-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260825155608
begin;

alter table public.payment_idempotency_keys enable row level security;
alter table public.payment_idempotency_keys force row level security;
revoke all on table public.payment_idempotency_keys from anon, authenticated;

commit;
;
