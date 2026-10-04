-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260823062437
alter table public.referral_program_config add column if not exists free_commission_amount numeric(14,2) not null default 10.00 check (free_commission_amount >= 0); alter table public.referral_program_config add column if not exists premium_commission_amount numeric(14,2) not null default 20.00 check (premium_commission_amount >= 0); update public.referral_program_config set enabled=true, free_commission_amount=10.00, premium_commission_amount=20.00, currency='ETB', eligibility='automatic_registration_invitation_tiered', updated_at=now() where id=true;
;
