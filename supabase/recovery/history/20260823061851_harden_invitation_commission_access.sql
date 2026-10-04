-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260823061851
alter table public.invitation_commissions enable row level security;
alter table public.registration_referrals enable row level security;
alter table public.referral_codes enable row level security;
alter table public.referral_program_config enable row level security;

drop policy if exists referral_codes_owner_select on public.referral_codes;
create policy referral_codes_owner_select on public.referral_codes for select to authenticated using (owner_user_id = auth.uid());

drop policy if exists registration_referrals_participant_select on public.registration_referrals;
create policy registration_referrals_participant_select on public.registration_referrals for select to authenticated using (registered_user_id = auth.uid() or inviter_user_id = auth.uid());

-- Commission rows stay server/admin-only. No direct client policy is granted.
-- Program configuration stays server/admin-only. No direct client policy is granted.

create or replace function public.create_invitation_commission_from_registration(p_registered_user_id uuid, p_invitation_code text, p_registration_id uuid default null)
returns public.invitation_commissions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code public.referral_codes%rowtype;
  v_cfg public.referral_program_config%rowtype;
  v_ref public.registration_referrals%rowtype;
  v_comm public.invitation_commissions%rowtype;
begin
  select * into v_cfg from public.referral_program_config where id = true for update;
  if not found or not v_cfg.enabled then return null; end if;
  select * into v_code from public.referral_codes where upper(code)=upper(trim(p_invitation_code)) and active=true limit 1;
  if not found or v_code.owner_user_id = p_registered_user_id then return null; end if;
  insert into public.registration_referrals(registered_user_id, inviter_user_id, referral_code_id, invitation_code)
  values(p_registered_user_id,v_code.owner_user_id,v_code.id,v_code.code)
  on conflict (registered_user_id) do nothing;
  select * into v_ref from public.registration_referrals where registered_user_id=p_registered_user_id limit 1;
  if v_ref.id is null or v_ref.inviter_user_id = p_registered_user_id then return null; end if;
  insert into public.invitation_commissions(inviter_user_id,registered_user_id,invitation_code,registration_id,amount,currency,status,transaction_reference,eligibility_reason)
  values(v_ref.inviter_user_id,p_registered_user_id,v_ref.invitation_code,p_registration_id,v_cfg.commission_amount,v_cfg.currency,'pending','INV-'||upper(replace(gen_random_uuid()::text,'-','')),'Eligible registration invitation')
  on conflict (registered_user_id) where status <> 'cancelled' do nothing
  returning * into v_comm;
  return v_comm;
end;
$$;
revoke all on function public.create_invitation_commission_from_registration(uuid,text,uuid) from public, anon, authenticated;

drop index if exists invitation_commissions_one_registration;
create unique index if not exists invitation_commissions_one_registration on public.invitation_commissions(registered_user_id) where status <> 'cancelled';
;
