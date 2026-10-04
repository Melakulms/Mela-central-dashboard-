-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260822104809
revoke execute on function public.request_my_guardian_consent(text,text,text) from authenticated;
;
