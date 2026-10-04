-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815071738
create table if not exists public.mela_learning_payment_attempts(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  product_key text not null references public.mela_learning_products(product_key) on delete restrict,
  provider text not null default 'chapa' check(provider='chapa'),
  mode text not null default 'test' check(mode in ('test','live')),
  tx_ref text not null unique,
  expected_amount_minor integer not null check(expected_amount_minor>0),
  expected_currency text not null check(expected_currency in ('ETB','USD')),
  status text not null default 'initiated' check(status in ('initiated','pending','success','failed','cancelled','expired')),
  checkout_url text,
  provider_status text,
  provider_ref text,
  provider_method text,
  provider_type text,
  provider_charge numeric,
  verify_payload jsonb,
  failure_reason text,
  entitlement_id uuid references public.mela_user_learning_entitlements(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  paid_at timestamptz,
  last_verified_at timestamptz
);
alter table public.mela_learning_payment_attempts enable row level security;
drop policy if exists mela_learning_payment_attempts_owner_read on public.mela_learning_payment_attempts;
create policy mela_learning_payment_attempts_owner_read on public.mela_learning_payment_attempts for select to authenticated using(user_id=(select auth.uid()) or private.is_admin_user());
create index if not exists mela_learning_payment_attempts_user_status_idx on public.mela_learning_payment_attempts(user_id,status,created_at desc);
create index if not exists mela_learning_payment_attempts_product_idx on public.mela_learning_payment_attempts(product_key,created_at desc);

create or replace function public.finalize_mela_learning_payment(
  p_payment_id uuid,
  p_provider_ref text,
  p_provider_method text,
  p_provider_type text,
  p_provider_charge numeric,
  p_verify_payload jsonb
) returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_pay public.mela_learning_payment_attempts%rowtype;
  v_prod public.mela_learning_products%rowtype;
  v_ent uuid;
  v_start timestamptz;
  v_end timestamptz;
  v_existing_end timestamptz;
begin
  select * into v_pay from public.mela_learning_payment_attempts where id=p_payment_id for update;
  if v_pay.id is null then raise exception 'payment attempt not found'; end if;
  select * into v_prod from public.mela_learning_products where product_key=v_pay.product_key;
  if v_prod.product_key is null then raise exception 'learning product not found'; end if;

  select id into v_ent from public.mela_user_learning_entitlements
   where user_id=v_pay.user_id and source='payment' and source_reference=v_pay.tx_ref
   order by created_at desc limit 1;

  if v_ent is null then
    v_start := now();
    if v_prod.product_type='subscription' then
      select max(ends_at) into v_existing_end from public.mela_user_learning_entitlements
       where user_id=v_pay.user_id and product_key=v_pay.product_key and status='active' and ends_at>now();
      if v_existing_end is not null then v_start:=v_existing_end; end if;
      if v_prod.billing_period='monthly' then v_end:=v_start+interval '1 month';
      elsif v_prod.billing_period='annual' then v_end:=v_start+interval '1 year';
      else raise exception 'unsupported subscription billing period'; end if;
    elsif v_prod.product_type='one_time' then
      v_end:=null;
    else
      raise exception 'product type not eligible for public checkout';
    end if;

    insert into public.mela_user_learning_entitlements(user_id,product_key,status,starts_at,ends_at,source,source_reference)
    values(v_pay.user_id,v_pay.product_key,'active',v_start,v_end,'payment',v_pay.tx_ref)
    returning id into v_ent;
  end if;

  update public.mela_learning_payment_attempts
   set status='success',provider_status='success',provider_ref=p_provider_ref,provider_method=p_provider_method,
       provider_type=p_provider_type,provider_charge=p_provider_charge,verify_payload=coalesce(p_verify_payload,'{}'::jsonb),
       failure_reason=null,entitlement_id=v_ent,paid_at=coalesce(paid_at,now()),last_verified_at=now(),updated_at=now()
   where id=v_pay.id;

  return jsonb_build_object('status','success','payment_id',v_pay.id,'tx_ref',v_pay.tx_ref,'product_key',v_pay.product_key,'entitlement_id',v_ent);
end;
$$;
revoke all on function public.finalize_mela_learning_payment(uuid,text,text,text,numeric,jsonb) from public,anon,authenticated;
grant execute on function public.finalize_mela_learning_payment(uuid,text,text,text,numeric,jsonb) to service_role;

;
