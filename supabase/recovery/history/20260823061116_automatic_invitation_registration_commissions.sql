-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260823061116
create table if not exists public.referral_program_config (
  id boolean primary key default true check (id),
  commission_amount numeric(14,2) not null default 0 check (commission_amount >= 0),
  currency text not null default 'ETB',
  enabled boolean not null default false,
  eligibility text not null default 'verified_registration',
  updated_at timestamptz not null default now()
);
insert into public.referral_program_config(id) values(true) on conflict(id) do nothing;

create table if not exists public.referral_codes (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete restrict,
  code text not null unique,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists referral_codes_owner_idx on public.referral_codes(owner_user_id);

create table if not exists public.registration_referrals (
  id uuid primary key default gen_random_uuid(),
  registered_user_id uuid not null unique references auth.users(id) on delete restrict,
  inviter_user_id uuid not null references auth.users(id) on delete restrict,
  referral_code_id uuid not null references public.referral_codes(id) on delete restrict,
  invitation_code text not null,
  created_at timestamptz not null default now(),
  constraint registration_referrals_not_self check (registered_user_id <> inviter_user_id)
);
create index if not exists registration_referrals_inviter_idx on public.registration_referrals(inviter_user_id,created_at desc);

alter table public.referral_program_config enable row level security;
alter table public.referral_codes enable row level security;
alter table public.registration_referrals enable row level security;

create or replace function public.process_registration_invitation(p_registered_user_id uuid,p_invitation_code text)
returns public.invitation_commissions
language plpgsql
security definer
set search_path=public
as $$
declare v_code public.referral_codes; v_cfg public.referral_program_config; v_ref public.registration_referrals; v_comm public.invitation_commissions;
begin
  if p_registered_user_id is null or nullif(trim(p_invitation_code),'') is null then return null; end if;
  select * into v_cfg from public.referral_program_config where id=true;
  if not coalesce(v_cfg.enabled,false) then return null; end if;
  select * into v_code from public.referral_codes where upper(code)=upper(trim(p_invitation_code)) and active=true limit 1;
  if v_code.id is null or v_code.owner_user_id=p_registered_user_id then return null; end if;
  insert into public.registration_referrals(registered_user_id,inviter_user_id,referral_code_id,invitation_code)
  values(p_registered_user_id,v_code.owner_user_id,v_code.id,v_code.code)
  on conflict(registered_user_id) do nothing
  returning * into v_ref;
  if v_ref.id is null then select * into v_ref from public.registration_referrals where registered_user_id=p_registered_user_id; end if;
  insert into public.invitation_commissions(inviter_user_id,registered_user_id,invitation_code,registration_id,amount,currency,status,transaction_reference,eligibility_reason)
  values(v_ref.inviter_user_id,p_registered_user_id,v_ref.invitation_code,v_ref.id,v_cfg.commission_amount,v_cfg.currency,'pending','INV-'||upper(replace(gen_random_uuid()::text,'-','')),'Registration invitation eligible')
  on conflict (registered_user_id) where status <> 'cancelled' do nothing
  returning * into v_comm;
  return v_comm;
end;
$$;
revoke all on function public.process_registration_invitation(uuid,text) from public,anon,authenticated;

create or replace function public.handle_new_auth_user_invitation()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  perform public.process_registration_invitation(new.id, new.raw_user_meta_data->>'invitation_code');
  return new;
end;
$$;

drop trigger if exists trg_auth_user_invitation_commission on auth.users;
create trigger trg_auth_user_invitation_commission
after insert on auth.users
for each row execute function public.handle_new_auth_user_invitation();

revoke all on function public.handle_new_auth_user_invitation() from public,anon,authenticated;
;
