-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260825154142
begin;

create table if not exists public.payment_idempotency_keys (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  idempotency_key text not null,
  operation text not null,
  request_hash text,
  payment_id uuid references public.payments(id) on delete set null,
  status text not null default 'processing' check (status in ('processing','completed','failed')),
  response jsonb,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  expires_at timestamptz not null default (now() + interval '24 hours'),
  unique (user_id, operation, idempotency_key)
);

create index if not exists payment_idempotency_expires_idx on public.payment_idempotency_keys(expires_at);
create index if not exists payment_idempotency_payment_idx on public.payment_idempotency_keys(payment_id);

revoke all on public.payment_idempotency_keys from anon, authenticated;

commit;
;
