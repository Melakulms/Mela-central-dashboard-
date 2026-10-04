-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260822092151
revoke insert,update,delete on public.applications from authenticated;
;
