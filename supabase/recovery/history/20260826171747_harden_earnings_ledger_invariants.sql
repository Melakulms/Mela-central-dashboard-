-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260826171747
ALTER TABLE public.earnings_ledger DROP CONSTRAINT IF EXISTS earnings_ledger_amounts_valid;
ALTER TABLE public.earnings_ledger ADD CONSTRAINT earnings_ledger_amounts_valid CHECK (gross_amount >= 0 AND platform_fee >= 0 AND platform_fee <= gross_amount AND net_amount = gross_amount - platform_fee AND net_amount >= 0);

CREATE OR REPLACE FUNCTION public.guard_earnings_ledger_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.user_id IS DISTINCT FROM OLD.user_id
       OR NEW.source_type IS DISTINCT FROM OLD.source_type
       OR NEW.source_id IS DISTINCT FROM OLD.source_id
       OR NEW.gross_amount IS DISTINCT FROM OLD.gross_amount
       OR NEW.platform_fee IS DISTINCT FROM OLD.platform_fee
       OR NEW.net_amount IS DISTINCT FROM OLD.net_amount
       OR NEW.currency IS DISTINCT FROM OLD.currency THEN
      IF NOT public.is_admin_user(auth.uid()) THEN
        RAISE EXCEPTION 'Earnings ledger identity and financial fields are immutable for non-admin users';
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_earnings_ledger_mutation ON public.earnings_ledger;
CREATE TRIGGER trg_guard_earnings_ledger_mutation
BEFORE UPDATE ON public.earnings_ledger
FOR EACH ROW EXECUTE FUNCTION public.guard_earnings_ledger_mutation();
;
