-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260924024310

-- Confirmed by direct reproduction: authenticated had SELECT on applications
-- but no INSERT at all, so no student could ever apply to an opportunity or
-- scholarship despite the RLS policy and frontend both being correct.
GRANT INSERT ON public.applications TO authenticated;

;
