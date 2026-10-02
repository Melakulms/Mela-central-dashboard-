-- Production-applied financial hardening.
-- Learning payment attempts are service-created only, and successful provider
-- references are unique so one provider transaction cannot settle twice.

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
