-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260903155749
REVOKE EXECUTE ON FUNCTION public.mela_ai_audit(uuid,text,text,uuid,jsonb) FROM PUBLIC, anon, authenticated; GRANT EXECUTE ON FUNCTION public.mela_ai_audit(uuid,text,text,uuid,jsonb) TO service_role;
;
