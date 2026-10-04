-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260825160329
begin;
revoke all on table public.referral_codes from anon, authenticated;
grant select on table public.referral_codes to authenticated;
commit;
;
