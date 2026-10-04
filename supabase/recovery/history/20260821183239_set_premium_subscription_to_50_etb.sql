-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260821183239
update public.subscription_plans set price_minor=5000,currency='ETB',billing_period_days=30,active=true,updated_at=now() where plan_key='premium_monthly';
;
