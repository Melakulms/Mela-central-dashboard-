-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260825155050
begin;

-- Users may manage their own payout destination, but ownership and activation
-- are server-controlled. Restrict client UPDATE to mutable destination fields.
revoke update on table public.payout_accounts from authenticated;
grant update (account_name, account_number, bank_code, bank_name, currency) on table public.payout_accounts to authenticated;

-- Keep activation/deactivation under trusted server/admin code.
revoke update (active) on table public.payout_accounts from authenticated;

commit;
;
