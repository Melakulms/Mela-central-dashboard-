-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260826135610
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relname='earnings_ledger' AND c.relkind='r') THEN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relname='earnings_ledger' AND t.tgname='trg_earnings_ledger_immutable_financial_fields') THEN
      CREATE TRIGGER trg_earnings_ledger_immutable_financial_fields BEFORE UPDATE ON public.earnings_ledger FOR EACH ROW EXECUTE FUNCTION private.guard_earnings_ledger_update();
    END IF;
  END IF;
EXCEPTION WHEN undefined_function THEN NULL; END $$;
;
