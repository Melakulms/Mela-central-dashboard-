-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260816062707
create unique index if not exists user_subscriptions_source_payment_uq on public.user_subscriptions(source_payment_attempt_id) where source_payment_attempt_id is not null;

create or replace function public.finalize_mela_learning_payment(p_payment_id uuid, p_provider_ref text, p_provider_method text, p_provider_type text, p_provider_charge numeric, p_verify_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_pay public.mela_learning_payment_attempts%rowtype;
  v_prod public.mela_learning_products%rowtype;
  v_ent uuid; v_start timestamptz; v_end timestamptz; v_existing_end timestamptz;
  v_plan uuid; v_sub uuid;
begin
  select * into v_pay from public.mela_learning_payment_attempts where id=p_payment_id for update;
  if v_pay.id is null then raise exception 'payment attempt not found'; end if;
  if v_pay.status='success' and v_pay.entitlement_id is not null then
    return jsonb_build_object('status','success','payment_id',v_pay.id,'tx_ref',v_pay.tx_ref,'product_key',v_pay.product_key,'entitlement_id',v_pay.entitlement_id,'idempotent',true);
  end if;
  select * into v_prod from public.mela_learning_products where product_key=v_pay.product_key;
  if v_prod.product_key is null then raise exception 'learning product not found'; end if;

  select id into v_ent from public.mela_user_learning_entitlements
   where user_id=v_pay.user_id and source='payment' and source_reference=v_pay.tx_ref order by created_at desc limit 1;
  if v_ent is null then
    v_start:=now();
    if v_prod.product_type='subscription' then
      select max(ends_at) into v_existing_end from public.mela_user_learning_entitlements
       where user_id=v_pay.user_id and status='active' and ends_at>now() and product_key=v_pay.product_key;
      if v_existing_end is not null then v_start:=v_existing_end; end if;
      if v_prod.billing_period='monthly' then v_end:=v_start+interval '1 month';
      elsif v_prod.billing_period='annual' then v_end:=v_start+interval '1 year';
      else raise exception 'unsupported subscription billing period'; end if;
    elsif v_prod.product_type='one_time' then v_end:=null;
    else raise exception 'product type not eligible for public checkout'; end if;
    insert into public.mela_user_learning_entitlements(user_id,product_key,status,starts_at,ends_at,source,source_reference)
    values(v_pay.user_id,v_pay.product_key,'active',v_start,v_end,'payment',v_pay.tx_ref) returning id into v_ent;
  end if;

  if v_prod.product_type='subscription' then
    insert into public.subscription_plans(plan_key,name,tier,price_minor,currency,billing_period_days,active,features)
    values(v_prod.product_key,v_prod.product_name,'premium',coalesce(v_prod.active_price_minor,v_pay.expected_amount_minor),v_prod.currency,
      case when v_prod.billing_period='annual' then 365 else 30 end,true,coalesce(v_prod.features,'{}'::jsonb))
    on conflict(plan_key) do update set name=excluded.name,tier='premium',price_minor=excluded.price_minor,currency=excluded.currency,billing_period_days=excluded.billing_period_days,features=excluded.features,updated_at=now()
    returning id into v_plan;

    select id into v_sub from public.user_subscriptions where source_payment_attempt_id=v_pay.id limit 1;
    if v_sub is null then
      update public.user_subscriptions set status=case when status='premium_active' then 'premium_expired' else 'cancelled' end,updated_at=now()
      where user_id=v_pay.user_id and status in ('free','premium_pending','premium_active');
      insert into public.user_subscriptions(user_id,plan_id,status,starts_at,expires_at,source_payment_attempt_id)
      values(v_pay.user_id,v_plan,'premium_active',v_start,v_end,v_pay.id) returning id into v_sub;
    end if;
    insert into public.notifications(user_id,title,body,ref_table,ref_id)
    select v_pay.user_id,'Premium activated','Your verified payment activated Mela Premium.','user_subscriptions',v_sub
    where not exists(select 1 from public.notifications where user_id=v_pay.user_id and ref_table='user_subscriptions' and ref_id=v_sub and title='Premium activated');
    insert into public.admin_audit_logs(actor_id,action,entity_type,entity_id,details)
    values(v_pay.user_id,'verified_subscription_activation','user_subscription',v_sub,jsonb_build_object('payment_id',v_pay.id,'tx_ref',v_pay.tx_ref,'product_key',v_pay.product_key,'expires_at',v_end));
  end if;

  update public.mela_learning_payment_attempts
   set status='success',provider_status='success',provider_ref=p_provider_ref,provider_method=p_provider_method,
       provider_type=p_provider_type,provider_charge=p_provider_charge,verify_payload=coalesce(p_verify_payload,'{}'::jsonb),
       failure_reason=null,entitlement_id=v_ent,paid_at=coalesce(paid_at,now()),last_verified_at=now(),updated_at=now()
   where id=v_pay.id;
  return jsonb_build_object('status','success','payment_id',v_pay.id,'tx_ref',v_pay.tx_ref,'product_key',v_pay.product_key,'entitlement_id',v_ent,'subscription_id',v_sub);
end $$;
revoke all on function public.finalize_mela_learning_payment(uuid,text,text,text,numeric,jsonb) from public,anon,authenticated;
grant execute on function public.finalize_mela_learning_payment(uuid,text,text,text,numeric,jsonb) to service_role;

create or replace function private.expire_mela_subscriptions_v35()
returns integer language plpgsql security definer set search_path='' as $$
declare v_count integer;
begin
 update public.user_subscriptions set status='premium_expired',updated_at=now()
 where status='premium_active' and expires_at is not null and expires_at<=now();
 get diagnostics v_count=row_count;
 insert into public.user_subscriptions(user_id,plan_id,status,starts_at)
 select p.id,sp.id,'free',now() from public.profiles p cross join public.subscription_plans sp
 where sp.plan_key='free' and not exists(select 1 from public.user_subscriptions us where us.user_id=p.id and us.status in ('free','premium_pending','premium_active'));
 return v_count;
end $$;
revoke all on function private.expire_mela_subscriptions_v35() from public,anon,authenticated;
;
