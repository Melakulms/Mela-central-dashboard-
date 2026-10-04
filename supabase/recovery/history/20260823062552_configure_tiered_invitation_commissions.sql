-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260823062552
alter table public.referral_program_config add column if not exists free_commission_amount numeric(14,2) not null default 10, add column if not exists premium_commission_amount numeric(14,2) not null default 20;
update public.referral_program_config set enabled=true, free_commission_amount=10, premium_commission_amount=20, currency='ETB', eligibility='automatic_registration_invitation_tiered', updated_at=now() where id=true;

create or replace function public.process_registration_invitation(p_registered_user_id uuid, p_invitation_code text)
returns public.invitation_commissions
language plpgsql security definer set search_path=public
as $$
declare v_code public.referral_codes; v_cfg public.referral_program_config; v_ref public.registration_referrals; v_comm public.invitation_commissions; v_ledger public.earnings_ledger; v_tier text; v_amount numeric(14,2);
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
 select case when exists(select 1 from public.user_subscriptions us join public.subscription_plans sp on sp.id=us.plan_id where us.user_id=p_registered_user_id and us.status='active' and sp.tier='premium' and us.expires_at>now()) then 'premium' else 'free' end into v_tier;
 v_amount := case when v_tier='premium' then v_cfg.premium_commission_amount else v_cfg.free_commission_amount end;
 if coalesce(v_amount,0)<=0 then return null; end if;
 insert into public.invitation_commissions(inviter_user_id,registered_user_id,invitation_code,registration_id,amount,currency,status,transaction_reference,eligibility_reason,paid_at,invitee_tier)
 values(v_ref.inviter_user_id,p_registered_user_id,v_ref.invitation_code,v_ref.id,v_amount,v_cfg.currency,'paid','INV-'||upper(replace(gen_random_uuid()::text,'-','')),'Automatic registration invitation commission ('||v_tier||')',now(),v_tier)
 on conflict (registered_user_id) where status <> 'cancelled' do nothing returning * into v_comm;
 if v_comm.id is null then select * into v_comm from public.invitation_commissions where registered_user_id=p_registered_user_id and status<>'cancelled' limit 1; return v_comm; end if;
 if not exists(select 1 from public.earnings_ledger where source_type='referral_reward' and source_id=v_comm.id) then
  insert into public.earnings_ledger(user_id,source_type,source_id,gross_amount,platform_fee,net_amount,currency,status,external_ref) values(v_comm.inviter_user_id,'referral_reward',v_comm.id,v_comm.amount,0,v_comm.amount,v_comm.currency,'available',v_comm.transaction_reference);
 end if;
 return v_comm;
end; $$;
revoke all on function public.process_registration_invitation(uuid,text) from public,anon,authenticated;
;
