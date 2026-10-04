-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260823111215
revoke all on table public.invitation_commissions from anon, authenticated;
revoke all on table public.referral_program_config from anon, authenticated;
;
