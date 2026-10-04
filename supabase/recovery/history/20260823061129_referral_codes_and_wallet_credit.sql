-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260823061129
create or replace function public.ensure_referral_code(p_user_id uuid)
returns text
language plpgsql
security definer
set search_path=public
as $$
declare v_code text; v_existing text;
begin
  select code into v_existing from public.referral_codes where owner_user_id=p_user_id and active=true order by created_at limit 1;
  if v_existing is not null then return v_existing; end if;
  v_code := 'MELA-'||upper(substr(replace(p_user_id::text,'-',''),1,10));
  insert into public.referral_codes(owner_user_id,code) values(p_user_id,v_code) on conflict(code) do nothing;
  select code into v_existing from public.referral_codes where owner_user_id=p_user_id and active=true order by created_at limit 1;
  return v_existing;
end;
$$;
revoke all on function public.ensure_referral_code(uuid) from public,anon,authenticated;

insert into public.referral_codes(owner_user_id,code)
select u.id,'MELA-'||upper(substr(replace(u.id::text,'-',''),1,10))
from auth.users u
where not exists(select 1 from public.referral_codes r where r.owner_user_id=u.id)
on conflict(code) do nothing;

create or replace function public.handle_new_auth_user_invitation()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  perform public.ensure_referral_code(new.id);
  perform public.process_registration_invitation(new.id,new.raw_user_meta_data->>'invitation_code');
  return new;
end;
$$;
revoke all on function public.handle_new_auth_user_invitation() from public,anon,authenticated;

create or replace function public.process_registration_invitation(p_registered_user_id uuid,p_invitation_code text)
returns public.invitation_commissions
language plpgsql
security definer
set search_path=public
as $$
declare v_code public.referral_codes; v_cfg public.referral_program_config; v_ref public.registration_referrals; v_comm public.invitation_commissions; v_ledger public.earnings_ledger;
begin
  if p_registered_user_id is null or nullif(trim(p_invitation_code),'') is null then return null; end if;
  select * into v_cfg from public.referral_program_config where id=true;
  if not coalesce(v_cfg.enabled,false) or v_cfg.commission_amount <= 0 then return null; end if;
  select * into v_code from public.referral_codes where upper(code)=upper(trim(p_invitation_code)) and active=true limit 1;
  if v_code.id is null or v_code.owner_user_id=p_registered_user_id then return null; end if;
  insert into public.registration_referrals(registered_user_id,inviter_user_id,referral_code_id,invitation_code)
  values(p_registered_user_id,v_code.owner_user_id,v_code.id,v_code.code)
  on conflict(registered_user_id) do nothing
  returning * into v_ref;
  if v_ref.id is null then select * into v_ref from public.registration_referrals where registered_user_id=p_registered_user_id; end if;
  insert into public.invitation_commissions(inviter_user_id,registered_user_id,invitation_code,registration_id,amount,currency,status,transaction_reference,eligibility_reason,paid_at)
  values(v_ref.inviter_user_id,p_registered_user_id,v_ref.invitation_code,v_ref.id,v_cfg.commission_amount,v_cfg.currency,'paid','INV-'||upper(replace(gen_random_uuid()::text,'-','')),'Automatic registration invitation commission',now())
  on conflict (registered_user_id) where status <> 'cancelled' do nothing
  returning * into v_comm;
  if v_comm.id is null then select * into v_comm from public.invitation_commissions where registered_user_id=p_registered_user_id and status <> 'cancelled' limit 1; end if;
  if not exists(select 1 from public.earnings_ledger where source_type='referral_reward' and source_id=v_comm.id) then
    insert into public.earnings_ledger(user_id,source_type,source_id,gross_amount,platform_fee,net_amount,currency,status,external_ref)
    values(v_comm.inviter_user_id,'referral_reward',v_comm.id,v_comm.amount,0,v_comm.amount,v_comm.currency,'available',v_comm.transaction_reference)
    returning * into v_ledger;
  end if;
  return v_comm;
end;
$$;
revoke all on function public.process_registration_invitation(uuid,text) from public,anon,authenticated;
;
