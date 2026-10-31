-- Prevent using the same independently verified bank reference twice across
-- all MELA money-processing paths, even where each has its own provider coding.
create unique index if not exists mela_billing_global_verified_bank_ref
 on mela_billing.orders(bank_reference_key) where bank_reference_key is not null and status in ('verified','reversed');

create or replace function public.mela_billing_review_v1(p_order_id uuid,p_action text,p_data jsonb)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare u uuid:=auth.uid(); v_order mela_billing.orders;
 v_ref text; v_key text; v_amount integer; v_note text;
 v_subscription uuid; v_prior boolean; v_referral public.registration_referrals;
 v_cfg public.referral_program_config; v_reward numeric; v_tier text;
begin
 if u is null or coalesce((auth.jwt()->>'aal'),'')<>'aal2'
 or coalesce((auth.jwt()->>'is_anonymous')::boolean,false)
 or not exists(select 1 from admin.admin_users where user_id=u and active)
 or not exists(select 1 from auth.mfa_factors where user_id=u and status='verified')
 or not exists(select 1 from auth.sessions where id::text=auth.jwt()->>'session_id' and user_id=u
   and (not_after is null or not_after>now()))
 then raise exception 'Active payment administrator with verified MFA is required' using errcode='42501'; end if;
 select * into v_order from mela_billing.orders where id=p_order_id for update;
 if v_order.id is null then raise exception 'Order not found'; end if;
 if v_order.status<>'pending_review' then raise exception 'Order already decided'; end if;
 if p_action not in ('verify','reject') then raise exception 'Invalid review action'; end if;
 v_note:=btrim(p_data->>'note');
 if v_note is null or length(v_note) not between 20 and 500
 then raise exception 'A detailed review note (20-500 characters) is required'; end if;
 if p_action='reject' then
   update mela_billing.orders set status='rejected',reviewer_id=u,review_note=v_note,
     reviewed_at=now(),updated_at=now() where id=p_order_id;
   return jsonb_build_object('id',p_order_id,'status','rejected');
 end if;
 if p_data->>'bank_confirmed' is distinct from 'true'
   or p_data->>'confirmed_payer' is distinct from 'true'
 then raise exception 'Bank receipt and correct payer must be confirmed independently'; end if;
 v_ref:=upper(btrim(p_data->>'bank_reference'));
 v_key:=regexp_replace(v_ref,'[^A-Z0-9]','','g');
 v_amount:=(p_data->>'bank_amount_minor')::integer;
 if v_ref is null or v_ref !~ '^[A-Z0-9][A-Z0-9-]{5,63}$' or length(v_key)<6
 then raise exception 'Invalid incoming bank reference'; end if;
 if v_amount is distinct from v_order.amount_minor
    or p_data->>'recipient' is distinct from v_order.recipient
 then raise exception 'Confirmed incoming amount or recipient mismatch'; end if;
 perform pg_advisory_xact_lock(hashtextextended('mela-used-bank-reference:'||v_key,0));
 perform pg_advisory_xact_lock(hashtextextended('mela-first-purchase:'||v_order.user_id::text,0));
 if exists(select 1 from mela_billing.orders where id<>p_order_id
      and bank_reference_key=v_key and status in ('verified','reversed'))
    or exists(select 1 from public.payment_submissions where normalized_ref=v_key and status='verified')
    or exists(select 1 from mela_telegram_payments.submissions
      where incoming_key=v_key and status='verified')
    or exists(select 1 from mela_payments.receipts
      where regexp_replace(upper(reference),'[^A-Z0-9]','','g')=v_key)
    or exists(select 1 from mela_bot_pilot.transfers
      where status='verified' and regexp_replace(upper(incoming_reference),'[^A-Z0-9]','','g')=v_key)
 then raise exception 'This transfer has already been verified in MELA'; end if;
 v_prior := exists(select 1 from mela_billing.orders
     where user_id=v_order.user_id and id<>p_order_id and status in ('verified','reversed'))
   or exists(select 1 from public.user_subscriptions where user_id=v_order.user_id
     and status='premium_active' and starts_at is not null)
   or exists(select 1 from public.mela_learning_payment_attempts where user_id=v_order.user_id
     and status='success' and paid_at is not null)
   or exists(select 1 from mela_payments.orders where user_id=v_order.user_id
     and status='approved');
 insert into public.user_subscriptions(user_id,plan_id,status,starts_at,expires_at)
 values(v_order.user_id,v_order.plan_id,'premium_active',now(),now()+interval '30 days')
 returning id into v_subscription;
 update mela_billing.orders set status='verified',bank_reference=v_ref,
   bank_reference_key=v_key,bank_confirmed_amount_minor=v_amount,
   reviewer_id=u,review_note=v_note,reviewed_at=now(),subscription_id=v_subscription,
   updated_at=now() where id=p_order_id;
 -- No spendable referral funds are created; this is an auditable pending claim.
 select * into v_cfg from public.referral_program_config where id=true;
 select * into v_referral from public.registration_referrals
  where registered_user_id=v_order.user_id and inviter_user_id<>v_order.user_id;
 if not v_prior and coalesce(v_cfg.enabled,false) and v_referral.id is not null then
   v_tier:=case when v_order.plan_key='pro_monthly' then 'pro' else 'premium' end;
   v_reward:=case when v_tier='pro' then 20 else 40 end;
   insert into public.invitation_commissions(inviter_user_id,registered_user_id,
    invitation_code,registration_id,amount,currency,status,transaction_reference,
    eligibility_reason,invitee_tier)
   values(v_referral.inviter_user_id,v_order.user_id,v_referral.invitation_code,
     v_referral.id,v_reward,'ETB','pending','INV-'||upper(replace(pg_catalog.gen_random_uuid()::text,'-','')),
     'First independently verified paid subscription; payout subject to review',v_tier)
   on conflict (registered_user_id) where status <> 'cancelled' do nothing;
 end if;
 return jsonb_build_object('id',p_order_id,'status','verified','subscription_id',v_subscription,
   'commission_status','pending_review_or_ineligible');
end $$;
revoke all on function public.mela_billing_review_v1(uuid,text,jsonb) from public,anon;
grant execute on function public.mela_billing_review_v1(uuid,text,jsonb) to authenticated;
-- Even service_role callers without an owner MFA session cannot approve by impersonation.
