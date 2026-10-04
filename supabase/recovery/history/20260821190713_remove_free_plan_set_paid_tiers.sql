-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260821190713
update public.subscription_plans set active=false, updated_at=now() where plan_key='free';
update public.subscription_plans set name='Mela Monthly', tier='normal', price_minor=2000, currency='ETB', billing_period_days=30, active=true, updated_at=now() where plan_key='normal_monthly';
update public.subscription_plans set name='Mela Premium Monthly', tier='premium', price_minor=5000, currency='ETB', billing_period_days=30, active=true, updated_at=now() where plan_key='premium_monthly';
;
