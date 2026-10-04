-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260903151935
revoke all on function public.mela_ai_audit(uuid,text,text,uuid,jsonb) from public;
;
