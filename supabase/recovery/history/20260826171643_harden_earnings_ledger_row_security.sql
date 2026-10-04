-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260826171643
ALTER TABLE public.earnings_ledger ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS earnings_ledger_select_own ON public.earnings_ledger;
CREATE POLICY earnings_ledger_select_own ON public.earnings_ledger FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()) OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = (SELECT auth.uid()) AND p.role = 'admin'));
REVOKE INSERT, UPDATE, DELETE ON public.earnings_ledger FROM authenticated, anon;
;
