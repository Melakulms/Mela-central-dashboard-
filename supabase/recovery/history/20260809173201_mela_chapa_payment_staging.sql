-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260809173201
create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  course_id uuid not null references public.courses(id) on delete restrict,
  provider text not null default 'chapa' check (provider = 'chapa'),
  mode text not null default 'test' check (mode in ('test','live')),
  tx_ref text not null unique,
  provider_ref text,
  expected_amount_cents integer not null check (expected_amount_cents > 0),
  expected_currency text not null check (expected_currency in ('ETB','USD')),
  status text not null default 'initiated' check (status in ('initiated','pending','success','failed','cancelled','expired')),
  checkout_url text,
  provider_status text,
  provider_method text,
  provider_type text,
  provider_charge numeric,
  verify_payload jsonb,
  failure_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  paid_at timestamptz,
  last_verified_at timestamptz
);

create index if not exists payments_user_created_idx on public.payments(user_id, created_at desc);
create index if not exists payments_course_idx on public.payments(course_id);
create unique index if not exists payments_one_success_per_user_course_idx on public.payments(user_id, course_id) where status = 'success';

alter table public.payments enable row level security;
drop policy if exists payments_self_select on public.payments;
create policy payments_self_select on public.payments for select to authenticated using ((select auth.uid()) = user_id);

grant select on public.payments to authenticated;
revoke insert, update, delete on public.payments from anon, authenticated;

create table if not exists private.payment_webhook_events (
  id uuid primary key default gen_random_uuid(),
  provider text not null default 'chapa',
  signature text not null,
  tx_ref text,
  payload jsonb not null,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  processing_result text,
  unique(provider, signature)
);
revoke all on private.payment_webhook_events from public, anon, authenticated;

create or replace function private.touch_payment_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
drop trigger if exists trg_touch_payment_updated_at on public.payments;
create trigger trg_touch_payment_updated_at before update on public.payments for each row execute function private.touch_payment_updated_at();

create or replace function private.prevent_payment_identity_change()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.user_id is distinct from old.user_id
     or new.course_id is distinct from old.course_id
     or new.tx_ref is distinct from old.tx_ref
     or new.expected_amount_cents is distinct from old.expected_amount_cents
     or new.expected_currency is distinct from old.expected_currency
     or new.provider is distinct from old.provider
     or new.mode is distinct from old.mode then
    raise exception 'payment identity fields are immutable';
  end if;
  return new;
end;
$$;
drop trigger if exists trg_prevent_payment_identity_change on public.payments;
create trigger trg_prevent_payment_identity_change before update on public.payments for each row execute function private.prevent_payment_identity_change();

create or replace view public.my_payment_history with (security_invoker = true) as
select p.id, p.course_id, c.slug as course_slug, c.title as course_title,
       p.tx_ref, p.expected_amount_cents, p.expected_currency, p.status,
       p.provider_status, p.provider_method, p.created_at, p.paid_at
from public.payments p
join public.courses c on c.id = p.course_id;
grant select on public.my_payment_history to authenticated;
revoke all on public.my_payment_history from anon;

;
