-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260826174031
REVOKE EXECUTE ON FUNCTION public.guard_earnings_ledger_mutation() FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.guard_learning_entitlement_identity() FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.guard_notification_update() FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.guard_subscription_financial_identity() FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.guard_task_message_update() FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.protect_freelance_contract_identity_and_financials() FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.protect_funded_milestone_financials() FROM anon, authenticated;

DROP POLICY IF EXISTS notifications_self_update_read_only ON public.notifications;
CREATE POLICY notifications_self_update_read_only ON public.notifications
FOR UPDATE TO authenticated
USING (user_id = (SELECT auth.uid()))
WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS earnings_ledger_select_own ON public.earnings_ledger;
;
