-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260826144811
REVOKE EXECUTE ON FUNCTION public.set_education_pilot_status(uuid,text) FROM anon, authenticated;
;
