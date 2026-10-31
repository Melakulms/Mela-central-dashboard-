-- MELA verified 50/100 ETB subscriptions; STAGING FIRST.
-- Manual bank confirmation is required, collection disabled by default.
-- No Telegram message, screenshot or claimed reference alone settles a purchase.
create schema if not exists mela_billing;
revoke all on schema mela_billing from public, anon, authenticated;
create table if not exists mela_billing.settings (
 singleton boolean primary key default true check (singleton),
 submissions_enabled boolean not null default false,
 updated_at timestamptz not null default now()
);
insert into mela_billing.settings(singleton,submissions_enabled)
values(true,false) on conflict(singleton) do nothing;

create table if not exists mela_billing.orders (
 id uuid primary key default pg_catalog.gen_random_uuid(),
 user_id uuid not null references public.profiles(id),
 plan_id uuid not null references public.subscription_plans(id),
 plan_key text not null check (plan_key in ('pro_monthly','premium_monthly')),
 amount_minor integer not null check (amount_minor in (5000,10000)),
 currency text not null default 'ETB' check(currency='ETB'),
 method_code text not null references public.payment_methods(code),
 recipient text not null,
 claimed_reference text,
 normalized_reference text,
 bank_reference text,
 bank_reference_key text,
 bank_confirmed_amount_minor integer,
 status text not null default 'draft'
   check (status in ('draft','pending_review','verified','rejected','reversed')),
 reviewer_id uuid references auth.users(id),
 review_note text,
 reviewed_at timestamptz,
 subscription_id uuid unique references public.user_subscriptions(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create unique index if not exists mela_billing_orders_claim_unique
 on mela_billing.orders(method_code,normalized_reference) where normalized_reference is not null and status <> 'rejected';
create unique index if not exists mela_billing_orders_bank_ref_unique
 on mela_billing.orders(method_code,bank_reference_key) where bank_reference_key is not null and status in ('verified','reversed');
create index if not exists mela_billing_orders_user_created
 on mela_billing.orders(user_id,created_at desc);
alter table mela_billing.settings enable row level security;
alter table mela_billing.orders enable row level security;
revoke all on all tables in schema mela_billing from public,anon,authenticated;

-- Attribution is created at signup, irrespective of the payout switch.
-- No monetary commission is created or credited at registration.
create or replace function public.process_registration_invitation(
 p_registered_user_id uuid,p_invitation_code text)
returns public.invitation_commissions
language plpgsql security definer set search_path=''
as $$
declare v_code public.referral_codes;
begin
 if p_registered_user_id is null or nullif(btrim(p_invitation_code),'') is null then return null; end if;
 select * into v_code from public.referral_codes
  where upper(code)=upper(btrim(p_invitation_code)) and active=true limit 1;
 if v_code.id is null or v_code.owner_user_id=p_registered_user_id then return null; end if;
 insert into public.registration_referrals(registered_user_id,inviter_user_id,referral_code_id,invitation_code)
 values(p_registered_user_id,v_code.owner_user_id,v_code.id,v_code.code)
 on conflict(registered_user_id) do nothing;
 return null;
end $$;
revoke all on function public.process_registration_invitation(uuid,text) from public,anon,authenticated;
grant execute on function public.process_registration_invitation(uuid,text) to service_role;
comment on function public.process_registration_invitation(uuid,text)
 is 'Records invitation attribution only. A trusted, first verified paid subscription may create one pending commission later.';

-- Label the lower paid tier correctly instead of using the legacy "free" category.
alter table public.invitation_commissions drop constraint if exists invitation_commissions_invitee_tier_check;
alter table public.invitation_commissions add constraint invitation_commissions_invitee_tier_check
 check (invitee_tier in ('free','pro','premium'));

create or replace function public.mela_billing_user_v1(p_action text,p_data jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare u uuid:=auth.uid(); v_plan public.subscription_plans;
 v_account public.payment_receiving_accounts; v_order mela_billing.orders;
 v_ref text; v_key text; v_count integer;
begin
 if u is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false)
   or not exists(select 1 from auth.users where id=u and email_confirmed_at is not null)
   or not exists(select 1 from public.profiles where id=u and deleted_at is null)
 then raise exception 'A verified MELA account is required' using errcode='42501'; end if;
 if p_action='plans' then
   return jsonb_build_object('submissions_open',(select submissions_enabled from mela_billing.settings where singleton=true),
    'plans',(select coalesce(jsonb_agg(jsonb_build_object(
       'key',plan_key,'name',name,'amount_etb',price_minor/100,'days',billing_period_days,
       'referral_etb',case when plan_key='pro_monthly' then 20 else 40 end)
       order by price_minor),'[]'::jsonb) from public.subscription_plans
       where plan_key in ('pro_monthly','premium_monthly') and active and currency='ETB'));
 elsif p_action='my_orders' then
   return coalesce((select jsonb_agg(x) from (
     select id,plan_key,amount_minor,status,created_at,reviewed_at from mela_billing.orders
     where user_id=u order by created_at desc limit 20) x),'[]'::jsonb);
 elsif p_action='create' then
   if not coalesce((select submissions_enabled from mela_billing.settings where singleton=true),false)
   then raise exception 'Payment collection is not open yet'; end if;
   select * into v_plan from public.subscription_plans
    where plan_key=p_data->>'plan_key' and plan_key in ('pro_monthly','premium_monthly')
      and active and currency='ETB' and billing_period_days=30;
   if v_plan.id is null or v_plan.price_minor is distinct from
      (case v_plan.plan_key when 'pro_monthly' then 5000 else 10000 end)
   then raise exception 'Invalid subscription plan or server price'; end if;
   select * into v_account from public.payment_receiving_accounts
    where active and method_code=p_data->>'method_code'
    order by display_order limit 1;
   if v_account.id is null then raise exception 'This payment method is unavailable'; end if;
   -- Guardian authorization requires a separate compliant workflow.
   if exists(select 1 from public.profiles where id=u and role='student'
       and coalesce(grade_level,0) between 1 and 12
       and learner_safety_status is distinct from 'adult')
    and not exists(select 1 from public.guardian_relationships
       where learner_id=u and status='verified')
   then raise exception 'Guardian verification is required before purchasing'; end if;
   select count(*) into v_count from mela_billing.orders
    where user_id=u and created_at>now()-interval '24 hours' and status in ('draft','pending_review');
   if v_count >= 5 then raise exception 'Daily order limit reached'; end if;
   insert into mela_billing.orders(user_id,plan_id,plan_key,amount_minor,method_code,recipient)
    values(u,v_plan.id,v_plan.plan_key,v_plan.price_minor,v_account.method_code,v_account.account_number)
    returning * into v_order;
   return jsonb_build_object('id',v_order.id,'status','draft','plan',v_order.plan_key,
    'amount_etb',v_order.amount_minor/100,'method',v_order.method_code,
    'recipient',v_order.recipient);
 elsif p_action='submit' then
   select * into v_order from mela_billing.orders
    where id=(p_data->>'order_id')::uuid and user_id=u for update;
   if v_order.id is null then raise exception 'Order not found'; end if;
   if v_order.status<>'draft' then raise exception 'Order was already submitted'; end if;
   if not (select submissions_enabled from mela_billing.settings where singleton=true)
   then raise exception 'Payment submissions are paused'; end if;
   v_ref:=upper(btrim(p_data->>'reference'));
   v_key:=regexp_replace(v_ref,'[^A-Z0-9]','','g');
   if v_ref is null or v_ref !~ '^[A-Z0-9][A-Z0-9-]{5,63}$'
       or length(v_key)<6 then raise exception 'Invalid transaction reference'; end if;
   update mela_billing.orders set claimed_reference=v_ref,normalized_reference=v_key,
      status='pending_review',updated_at=now() where id=v_order.id;
   return jsonb_build_object('id',v_order.id,'status','pending_review',
     'message','A claim is not proof of payment. Await bank-verified manual review.');
 else raise exception 'Unknown action'; end if;
end $$;
revoke all on function public.mela_billing_user_v1(text,jsonb) from public,anon;
grant execute on function public.mela_billing_user_v1(text,jsonb) to authenticated;
-- Never expose any unrestricted service-key financial mutation function to clients.

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
 perform pg_advisory_xact_lock(hashtextextended(v_order.method_code||':'||v_order.recipient||':'||v_key,0));
 perform pg_advisory_xact_lock(hashtextextended('mela-first-purchase:'||v_order.user_id::text,0));
 if exists(select 1 from mela_billing.orders where id<>p_order_id
      and method_code=v_order.method_code and recipient=v_order.recipient
      and bank_reference_key=v_key and status in ('verified','reversed'))
    or exists(select 1 from public.payment_submissions where normalized_ref=v_key
      and method_code=v_order.method_code and status='verified')
 then raise exception 'This transfer has already been verified in MELA'; end if;
 v_prior := exists(select 1 from mela_billing.orders
     where user_id=v_order.user_id and id<>p_order_id and status in ('verified','reversed'))
   or exists(select 1 from public.user_subscriptions where user_id=v_order.user_id
     and status='premium_active' and starts_at is not null);
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
