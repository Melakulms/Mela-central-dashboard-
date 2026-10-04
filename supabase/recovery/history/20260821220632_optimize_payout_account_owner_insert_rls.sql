-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260821220632
DROP POLICY IF EXISTS "Payout account owner insert" ON public.payout_accounts;
CREATE POLICY "Payout account owner insert"
ON public.payout_accounts
FOR INSERT TO authenticated
WITH CHECK ((user_id = (SELECT auth.uid())) AND (COALESCE(active, false) = false));
;
