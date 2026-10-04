-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260822062039
revoke insert, update, delete on table public.mela_user_learning_entitlements from authenticated; revoke insert, update, delete on table public.user_subscriptions from authenticated; revoke insert, update, delete on table public.subscription_plans from authenticated; revoke delete on table public.mela_learning_payment_attempts from authenticated;
;
