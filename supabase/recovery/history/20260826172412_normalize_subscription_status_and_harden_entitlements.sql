-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260826172412
ALTER TABLE public.user_subscriptions DROP CONSTRAINT IF EXISTS user_subscriptions_status_valid;
ALTER TABLE public.user_subscriptions ADD CONSTRAINT user_subscriptions_status_valid CHECK (status IN ('free','pending','active','expired','cancelled','past_due','paused'));

CREATE OR REPLACE FUNCTION public.guard_subscription_financial_identity()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF TG_OP='UPDATE' THEN
    IF NEW.user_id IS DISTINCT FROM OLD.user_id
       OR NEW.plan_id IS DISTINCT FROM OLD.plan_id
       OR NEW.source_payment_attempt_id IS DISTINCT FROM OLD.source_payment_attempt_id THEN
      IF NOT public.is_admin_user(auth.uid()) THEN
        RAISE EXCEPTION 'Subscription ownership, plan, and payment source are immutable for non-admin users';
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_guard_subscription_financial_identity ON public.user_subscriptions;
CREATE TRIGGER trg_guard_subscription_financial_identity BEFORE UPDATE ON public.user_subscriptions FOR EACH ROW EXECUTE FUNCTION public.guard_subscription_financial_identity();

CREATE OR REPLACE FUNCTION public.guard_learning_entitlement_identity()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF TG_OP='UPDATE' AND NOT public.is_admin_user(auth.uid()) THEN
    IF NEW.user_id IS DISTINCT FROM OLD.user_id OR NEW.product_key IS DISTINCT FROM OLD.product_key OR NEW.source IS DISTINCT FROM OLD.source OR NEW.source_reference IS DISTINCT FROM OLD.source_reference THEN
      RAISE EXCEPTION 'Learning entitlement identity is immutable for non-admin users';
    END IF;
  END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_guard_learning_entitlement_identity ON public.mela_user_learning_entitlements;
CREATE TRIGGER trg_guard_learning_entitlement_identity BEFORE UPDATE ON public.mela_user_learning_entitlements FOR EACH ROW EXECUTE FUNCTION public.guard_learning_entitlement_identity();
;
