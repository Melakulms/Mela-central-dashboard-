-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812211652
revoke update (role) on table public.profiles from authenticated;
;
