-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20261002210520
drop policy if exists mela_payment_attempts_owner_insert on public.mela_learning_payment_attempts;
revoke insert on table public.mela_learning_payment_attempts from authenticated;

grant select on table public.mela_learning_payment_attempts to authenticated;

create unique index if not exists escrow_payment_success_provider_ref_uidx
  on public.escrow_payment_attempts(provider_ref)
  where status='success' and provider_ref is not null;

create unique index if not exists learning_payment_success_provider_ref_uidx
  on public.mela_learning_payment_attempts(provider_ref)
  where status='success' and provider_ref is not null;

create unique index if not exists payout_success_provider_ref_uidx
  on public.payout_requests(provider_ref)
  where status='success' and provider_ref is not null;
;
