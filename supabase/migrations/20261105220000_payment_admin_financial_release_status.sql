-- Owner-only MFA payment readiness now shows release-gate statuses.
-- No payment status, provider configuration, order, payout or proof is changed.
-- Preserve the original RPC access checks and mutation semantics.
CREATE OR REPLACE FUNCTION public.mela_payment_readiness_v1(p_action text, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid:=auth.uid(); v_acc mela_payments.accounts%rowtype;
  v_note text; v_count int;
begin
  if v_actor is null
    or coalesce((auth.jwt()->>'is_anonymous')::boolean,false)
    or (auth.jwt()->>'aal') is distinct from 'aal2'
    or not exists(select 1 from auth.mfa_factors where user_id=v_actor and status='verified')
    or not exists(select 1 from auth.sessions where user_id=v_actor
         and id::text=auth.jwt()->>'session_id' and (not_after is null or not_after>now()))
    or not exists(select 1 from admin.admin_users where user_id=v_actor and active)
    or not exists(select 1 from mela_payments.reviewers where user_id=v_actor and active)
  then raise exception 'Active administrator with verified MFA and payment reviewer permission required'
    using errcode='42501'; end if;

  if p_action='status' then
    return jsonb_build_object(
      'financial_launch_approved', coalesce(private.mela_financial_launch_approved(), false),
      'financial_release_requirements', (
        select coalesce(jsonb_agg(jsonb_build_object(
          'requirement_key',r.requirement_key,
          'status',r.manual_status,
          'required',r.required,
          'evidence_recorded',r.completed_by is not null and r.completed_at is not null
            and length(btrim(coalesce(r.evidence_note, ''))) >= 40
        ) order by r.requirement_key),'[]'::jsonb)
        from public.platform_launch_requirements r
        where r.requirement_key in ('payments_provider','legal_review','wallet_business_legal')
      ),
      'checkout_enabled',coalesce((select enabled from mela_payments.settings where singleton),false),
      'platform_payments_enabled',coalesce((select enabled from public.platform_feature_flags where feature_key='payments'),false),
      'payouts_enabled',coalesce((select enabled from public.platform_feature_flags where feature_key='payouts'),false),
      'active_reviewers',(select count(*) from mela_payments.reviewers where active),
      'paid_products',(select coalesce(jsonb_agg(jsonb_build_object(
          'title',p.title,'amount_minor',p.amount_minor,'active',p.active,'product_key',p.product_key)
          order by p.amount_minor),'[]'::jsonb) from mela_payments.products p
          where p.product_key in ('mela_pro_monthly','mela_premium_monthly')),
      'accounts',(select coalesce(jsonb_agg(jsonb_build_object(
          'id',a.id,'provider',a.provider,'recipient',a.recipient,'label',a.label,
          'active',a.active,'verified',(v.account_id is not null and v.revoked_at is null
             and v.recipient=a.recipient and v.provider=a.provider)) order by a.provider),'[]'::jsonb)
         from mela_payments.accounts a
         left join mela_payments.account_verifications v on v.account_id=a.id
         where a.provider in ('dashen','telebirr'))
    );
  end if;

  if p_data is null or jsonb_typeof(p_data)<>'object' then
    raise exception 'Invalid payment setup request'; end if;
  if p_action not in ('verify_account','deactivate_account') then
    raise exception 'Only account verification, deactivation and read-only status are allowed';
  end if;
  select * into v_acc from mela_payments.accounts
    where id=(p_data->>'account_id')::uuid and provider in ('dashen','telebirr')
    for update;
  if v_acc.id is null then raise exception 'Known Telebirr or Dashen receiving account required'; end if;

  if p_action='verify_account' then
    if (p_data->>'confirmed_control') is distinct from 'true'
      or (p_data->>'confirmed_account_owner') is distinct from 'true'
      or (p_data->>'confirmed_correct_recipient') is distinct from 'true'
    then raise exception 'Confirm actual access, bank account ownership, and exact recipient'; end if;
    v_note:=trim(p_data->>'evidence_note');
    if v_note is null or length(v_note) not between 40 and 500
       then raise exception 'A private, specific 40-500 character account verification note is required'; end if;
    insert into mela_payments.account_verifications
      (account_id,provider,recipient,reviewer_id,evidence_note,verified_at,revoked_at)
     values(v_acc.id,v_acc.provider,v_acc.recipient,v_actor,v_note,now(),null)
    on conflict (account_id) do update set
      provider=excluded.provider,recipient=excluded.recipient,
      reviewer_id=excluded.reviewer_id,evidence_note=excluded.evidence_note,
      verified_at=now(),revoked_at=null;
    update mela_payments.accounts set active=true where id=v_acc.id;
    insert into mela_payments.audit(order_id,actor,action,detail)
    values(null,v_actor,'receiving_account_verified',
      'Reviewer confirmed control and ownership of '||v_acc.provider||' account');
    return jsonb_build_object('account_id',v_acc.id,'status','verified',
      'checkout_enabled',(select enabled from mela_payments.settings where singleton));
  end if;

  update mela_payments.accounts set active=false where id=v_acc.id;
  update mela_payments.account_verifications set revoked_at=now()
   where account_id=v_acc.id and revoked_at is null;
  insert into mela_payments.audit(order_id,actor,action,detail)
   values(null,v_actor,'receiving_account_deactivated',
     'Reviewer deactivated '||v_acc.provider||' receiving account');
  return jsonb_build_object('account_id',v_acc.id,'status','deactivated');
end $function$

