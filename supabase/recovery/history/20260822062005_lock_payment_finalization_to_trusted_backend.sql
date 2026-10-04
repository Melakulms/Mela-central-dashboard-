-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260822062005
revoke execute on function public.finalize_mela_learning_payment(uuid,text,text,text,numeric,jsonb) from public, anon, authenticated; grant execute on function public.finalize_mela_learning_payment(uuid,text,text,text,numeric,jsonb) to service_role;
;
