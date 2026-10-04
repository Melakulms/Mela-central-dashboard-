-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260826170554
CREATE OR REPLACE FUNCTION public.protect_freelance_contract_identity_and_financials()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, private AS $$
BEGIN
  IF NOT private.is_admin_user() AND OLD.status <> 'pending' THEN
    IF NEW.task_id IS DISTINCT FROM OLD.task_id
       OR NEW.employer_id IS DISTINCT FROM OLD.employer_id
       OR NEW.freelancer_id IS DISTINCT FROM OLD.freelancer_id
       OR NEW.submission_id IS DISTINCT FROM OLD.submission_id
       OR NEW.agreed_amount IS DISTINCT FROM OLD.agreed_amount
       OR NEW.currency IS DISTINCT FROM OLD.currency THEN
      RAISE EXCEPTION 'Active contract identity and agreed financial terms are immutable';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_protect_freelance_contract_identity_financials ON public.freelance_contracts;
CREATE TRIGGER trg_protect_freelance_contract_identity_financials
BEFORE UPDATE ON public.freelance_contracts
FOR EACH ROW EXECUTE FUNCTION public.protect_freelance_contract_identity_and_financials();

CREATE OR REPLACE FUNCTION public.protect_funded_milestone_financials()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, private AS $$
BEGIN
  IF NOT private.is_admin_user() AND EXISTS (
    SELECT 1 FROM public.escrow_transactions e
    WHERE e.milestone_id = OLD.id
      AND e.status <> 'pending_funding'
  ) THEN
    IF NEW.amount IS DISTINCT FROM OLD.amount
       OR NEW.contract_id IS DISTINCT FROM OLD.contract_id THEN
      RAISE EXCEPTION 'Funded milestone identity and amount are immutable';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_protect_funded_milestone_financials ON public.task_milestones;
CREATE TRIGGER trg_protect_funded_milestone_financials
BEFORE UPDATE ON public.task_milestones
FOR EACH ROW EXECUTE FUNCTION public.protect_funded_milestone_financials();
;
