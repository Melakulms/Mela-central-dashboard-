-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260822104430
revoke execute on function private.update_external_application_status_v12(uuid,text,text,text,timestamptz) from authenticated; revoke execute on function public.update_external_application_status_v12(uuid,text,text,text,timestamptz) from authenticated;
;
