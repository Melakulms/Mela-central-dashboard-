-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260825155907
begin;
revoke all on table public.registration_referrals from anon, authenticated;
grant select on table public.registration_referrals to authenticated;
commit;
;
