-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260821183245
alter table public.subscription_plans drop constraint if exists subscription_plans_tier_check;
alter table public.subscription_plans add constraint subscription_plans_tier_check check (tier = any (array['free'::text,'normal'::text,'premium'::text]));
insert into public.subscription_plans(plan_key,name,tier,price_minor,currency,billing_period_days,active,features)
values('normal_monthly','Mela Normal Monthly','normal',2000,'ETB',30,true,'{}'::jsonb)
on conflict (plan_key) do update set name=excluded.name,tier=excluded.tier,price_minor=excluded.price_minor,currency=excluded.currency,billing_period_days=excluded.billing_period_days,active=true,updated_at=now();
;
