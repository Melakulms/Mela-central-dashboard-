set lock_timeout='5s';

CREATE OR REPLACE FUNCTION public.process_registration_invitation(p_registered_user_id uuid, p_invitation_code text)
 RETURNS invitation_commissions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_code public.referral_codes;
  v_cfg public.referral_program_config;
  v_ref public.registration_referrals;
  v_comm public.invitation_commissions;
  v_tier text;
  v_amount numeric(14,2);
begin
  if p_registered_user_id is null or nullif(trim(p_invitation_code),'') is null then return null; end if;
  select * into v_cfg from public.referral_program_config where id=true;
  if not coalesce(v_cfg.enabled,false) then return null; end if;
  select * into v_code from public.referral_codes where upper(code)=upper(trim(p_invitation_code)) and active=true limit 1;
  if v_code.id is null or v_code.owner_user_id=p_registered_user_id then return null; end if;
  insert into public.registration_referrals(registered_user_id,inviter_user_id,referral_code_id,invitation_code)
  values(p_registered_user_id,v_code.owner_user_id,v_code.id,v_code.code)
  on conflict(registered_user_id) do nothing;
  select * into v_ref from public.registration_referrals where registered_user_id=p_registered_user_id;
  if v_ref.id is null or v_ref.inviter_user_id=p_registered_user_id then return null; end if;
  select case when exists(
    select 1 from public.user_subscriptions us
    join public.subscription_plans sp on sp.id=us.plan_id
    where us.user_id=p_registered_user_id
      and us.status='premium_active'
      and sp.tier='premium'
      and us.expires_at>now()
  ) then 'premium' else 'free' end into v_tier;
  v_amount := case when v_tier='premium' then v_cfg.premium_commission_amount else v_cfg.free_commission_amount end;
  if coalesce(v_amount,0)<=0 then return null; end if;
  insert into public.invitation_commissions(inviter_user_id,registered_user_id,invitation_code,registration_id,amount,currency,status,transaction_reference,eligibility_reason,paid_at,invitee_tier)
  values(v_ref.inviter_user_id,p_registered_user_id,v_ref.invitation_code,v_ref.id,v_amount,v_cfg.currency,'pending','INV-'||upper(replace(pg_catalog.gen_random_uuid()::text,'-','')),'Pending verified payment and fraud review ('||v_tier||')',null,v_tier)
  on conflict (registered_user_id) where status <> 'cancelled' do nothing
  returning * into v_comm;
  if v_comm.id is null then
    select * into v_comm from public.invitation_commissions where registered_user_id=p_registered_user_id and status<>'cancelled' limit 1;
    return v_comm;
  end if;
  return v_comm;
end;
$function$
;
revoke execute on function public.process_registration_invitation(uuid,text) from public,anon,authenticated;
grant execute on function public.process_registration_invitation(uuid,text) to service_role;
comment on function public.process_registration_invitation(uuid,text) is 'Records referral attribution and a provisional pending commission. Never credits withdrawable earnings at sign-up; verified payment settlement and fraud review are required.';
