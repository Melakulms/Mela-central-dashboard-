-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260821220332
CREATE OR REPLACE FUNCTION private.guard_payout_account_activation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
begin
  if coalesce(new.active,false) = true
     and coalesce(old.active,false) = false
     and not private.is_admin_user() then
    raise exception 'Payout account activation requires platform verification.' using errcode='42501';
  end if;
  return new;
end;
$function$;

DROP TRIGGER IF EXISTS trg_guard_payout_account_activation ON public.payout_accounts;
CREATE TRIGGER trg_guard_payout_account_activation
BEFORE UPDATE ON public.payout_accounts
FOR EACH ROW EXECUTE FUNCTION private.guard_payout_account_activation();

DROP POLICY IF EXISTS "Payout account owner insert" ON public.payout_accounts;
CREATE POLICY "Payout account owner insert"
ON public.payout_accounts
FOR INSERT TO authenticated
WITH CHECK ((user_id = auth.uid()) AND coalesce(active,false) = false);

;
