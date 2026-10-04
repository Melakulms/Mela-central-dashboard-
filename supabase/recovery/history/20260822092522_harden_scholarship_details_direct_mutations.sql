-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260822092522
revoke insert,update,delete on public.scholarship_details from authenticated;
;
